package com.onyx.terminal.sftp

import android.content.Context
import com.onyx.terminal.service.NotificationHelper
import com.onyx.terminal.service.TransferService
import com.onyx.terminal.util.Logger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class TransferItem(
    val id: String,
    val sessionId: String,
    val direction: String,
    val localPath: String,
    val remotePath: String,
    val name: String,
    @Volatile var total: Long,
    val createdAt: Long
) {
    @Volatile
    var done: Long = 0L

    @Volatile
    var state: String = "queued"

    @Volatile
    var error: String? = null

    @Volatile
    var speed: Double = 0.0

    @Volatile
    var attempts: Int = 0

    fun toMap(): Map<String, Any?> {
        val remaining = (total - done).coerceAtLeast(0L)
        val eta = if (speed > 1.0 && state == "running") (remaining / speed).toLong() else -1L
        return mapOf(
            "id" to id,
            "sessionId" to sessionId,
            "direction" to direction,
            "localPath" to localPath,
            "remotePath" to remotePath,
            "name" to name,
            "total" to total,
            "done" to done,
            "state" to state,
            "error" to error,
            "speed" to speed,
            "etaSec" to eta,
            "attempts" to attempts,
            "createdAt" to createdAt
        )
    }
}

class TransferQueue(
    private val context: Context,
    private val manager: ConnectionManager,
    private val emit: (Map<String, Any?>) -> Unit
) {
    private val items = LinkedHashMap<String, TransferItem>()
    private val jobs = ConcurrentHashMap<String, Job>()
    private val lock = Any()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Volatile
    var concurrency: Int = 2

    @Volatile
    private var lastServiceSync = 0L

    @Volatile
    private var finishedSinceIdle = 0

    @Volatile
    private var failedSinceIdle = 0

    init {
        TransferService.onCancelAll = { cancelAll() }
    }

    fun list(): List<Map<String, Any?>> = synchronized(lock) { items.values.map { it.toMap() } }

    fun enqueueUpload(sessionId: String, local: File, remotePath: String): String {
        val item = TransferItem(
            UUID.randomUUID().toString(), sessionId, "upload", local.absolutePath,
            remotePath, local.name, local.length(), System.currentTimeMillis()
        )
        add(item)
        return item.id
    }

    fun enqueueDownload(sessionId: String, remotePath: String, local: File, size: Long): String {
        val item = TransferItem(
            UUID.randomUUID().toString(), sessionId, "download", local.absolutePath,
            remotePath, RemotePath.name(remotePath), size, System.currentTimeMillis()
        )
        add(item)
        return item.id
    }

    fun enqueueUploadTree(sessionId: String, localDir: File, remoteDir: String): Int {
        val fs = manager.fs(sessionId)
        val base = RemotePath.join(remoteDir, localDir.name)
        fs.mkdir(base)
        var count = 0
        for (file in localDir.walkTopDown().onEnter { it.canRead() }) {
            if (count >= MAX_TREE) break
            val relative = file.relativeTo(localDir).path.replace(File.separatorChar, '/')
            if (relative.isEmpty()) continue
            val target = RemotePath.join(base, relative)
            if (file.isDirectory) {
                fs.mkdir(target)
            } else if (file.isFile) {
                enqueueUpload(sessionId, file, target)
                count++
            }
        }
        return count
    }

    fun enqueueDownloadTree(sessionId: String, remoteDir: String, localDir: File): Int {
        val fs = manager.fs(sessionId)
        val base = File(localDir, RemotePath.name(remoteDir))
        base.mkdirs()
        var count = 0
        fun walk(remote: String, local: File) {
            for (entry in fs.list(remote)) {
                if (count >= MAX_TREE) return
                if (entry.isDir) {
                    val sub = File(local, entry.name)
                    sub.mkdirs()
                    walk(entry.path, sub)
                } else {
                    enqueueDownload(sessionId, entry.path, File(local, entry.name), entry.size)
                    count++
                }
            }
        }
        walk(remoteDir, base)
        return count
    }

    fun pause(id: String) {
        val item = find(id) ?: return
        if (item.state == "running" || item.state == "queued") {
            item.state = "paused"
            jobs[id]?.cancel()
            emitItem(item)
        }
    }

    fun resume(id: String) {
        val item = find(id) ?: return
        if (item.state == "paused" || item.state == "error" || item.state == "canceled") {
            item.state = "queued"
            item.error = null
            emitItem(item)
            pump()
        }
    }

    fun retry(id: String) = resume(id)

    fun cancel(id: String) {
        val item = find(id) ?: return
        if (item.state != "done") {
            item.state = "canceled"
            jobs[id]?.cancel()
            emitItem(item)
        }
    }

    fun cancelAll() {
        val snapshot = synchronized(lock) { items.values.toList() }
        for (item in snapshot) {
            if (item.state == "running" || item.state == "queued") cancel(item.id)
        }
    }

    fun clearFinished() {
        synchronized(lock) {
            val iterator = items.values.iterator()
            while (iterator.hasNext()) {
                val state = iterator.next().state
                if (state == "done" || state == "canceled" || state == "error") iterator.remove()
            }
        }
        emit(mapOf("type" to "queue"))
    }

    fun dispose() {
        TransferService.onCancelAll = null
        scope.cancel()
    }

    private fun find(id: String): TransferItem? = synchronized(lock) { items[id] }

    private fun add(item: TransferItem) {
        synchronized(lock) { items[item.id] = item }
        emitItem(item)
        pump()
    }

    private fun pump() {
        while (true) {
            val next: TransferItem
            synchronized(lock) {
                val running = items.values.count { it.state == "running" }
                if (running >= concurrency) return
                next = items.values.firstOrNull { it.state == "queued" } ?: return
                next.state = "running"
            }
            start(next)
        }
    }

    private fun start(item: TransferItem) {
        item.error = null
        item.attempts++
        emitItem(item)
        val job = scope.launch {
            var lastEmit = 0L
            var lastDone = item.done
            var lastTime = System.currentTimeMillis()
            try {
                val fs = manager.fs(item.sessionId)
                val progress: (Long) -> Unit = { done ->
                    if (!isActive) throw CancellationException("Transfer dihentikan")
                    item.done = done
                    val now = System.currentTimeMillis()
                    if (now - lastEmit >= 250) {
                        val seconds = (now - lastTime) / 1000.0
                        if (seconds > 0) {
                            val instant = (done - lastDone) / seconds
                            item.speed = if (item.speed == 0.0) instant else item.speed * 0.6 + instant * 0.4
                        }
                        lastTime = now
                        lastDone = done
                        lastEmit = now
                        emitItem(item)
                        syncService()
                    }
                }
                if (item.direction == "upload") {
                    val local = File(item.localPath)
                    item.total = local.length()
                    val parent = RemotePath.parent(item.remotePath)
                    try {
                        fs.mkdir(parent)
                    } catch (_: Exception) {
                    }
                    fs.upload(local, item.remotePath, item.done, progress)
                } else {
                    fs.download(item.remotePath, File(item.localPath), item.done, progress)
                    val finalSize = File(item.localPath).length()
                    if (finalSize > item.total) item.total = finalSize
                }
                item.done = item.total.coerceAtLeast(item.done)
                item.speed = 0.0
                item.state = "done"
                finishedSinceIdle++
            } catch (cancelled: CancellationException) {
                item.speed = 0.0
                if (item.state == "running") item.state = "paused"
            } catch (error: Throwable) {
                Logger.w("transfer", "Transfer ${item.name} gagal", error)
                item.speed = 0.0
                item.state = "error"
                item.error = error.message ?: error.javaClass.simpleName
                failedSinceIdle++
            } finally {
                jobs.remove(item.id)
                emitItem(item)
                afterChange()
            }
        }
        jobs[item.id] = job
    }

    private fun afterChange() {
        pump()
        val active = activeCount()
        if (active == 0) {
            TransferService.sync(context, 0, 0)
            if (finishedSinceIdle + failedSinceIdle > 0) {
                val title = if (failedSinceIdle == 0) "Transfer selesai" else "Transfer selesai dengan galat"
                NotificationHelper.alert(
                    context,
                    9000,
                    title,
                    "$finishedSinceIdle berkas berhasil, $failedSinceIdle gagal"
                )
                finishedSinceIdle = 0
                failedSinceIdle = 0
            }
        } else {
            syncService(force = true)
        }
        emit(mapOf("type" to "queue", "active" to active))
    }

    private fun activeCount(): Int =
        synchronized(lock) { items.values.count { it.state == "running" || it.state == "queued" } }

    private fun syncService(force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastServiceSync < 1000) return
        lastServiceSync = now
        var active = 0
        var total = 0L
        var done = 0L
        synchronized(lock) {
            for (item in items.values) {
                if (item.state == "running" || item.state == "queued") {
                    active++
                    total += item.total
                    done += item.done
                }
            }
        }
        val percent = if (total > 0) ((done * 100) / total).toInt() else 0
        TransferService.sync(context, active, percent)
    }

    private fun emitItem(item: TransferItem) {
        val map = HashMap<String, Any?>(item.toMap())
        map["type"] = "transfer"
        emit(map)
    }

    companion object {
        private const val MAX_TREE = 50_000
    }
}
