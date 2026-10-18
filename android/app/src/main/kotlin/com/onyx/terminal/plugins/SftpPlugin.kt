package com.onyx.terminal.plugins

import android.content.Context
import com.onyx.terminal.sftp.ConnectionManager
import com.onyx.terminal.sftp.FolderSync
import com.onyx.terminal.sftp.TransferQueue
import com.onyx.terminal.util.Channels
import com.onyx.terminal.util.Disposable
import com.onyx.terminal.util.EventBridge
import com.onyx.terminal.util.Limits
import com.onyx.terminal.util.OnyxException
import com.onyx.terminal.util.bool
import com.onyx.terminal.util.int
import com.onyx.terminal.util.long
import com.onyx.terminal.util.map
import com.onyx.terminal.util.reply
import com.onyx.terminal.util.requireStr
import com.onyx.terminal.util.str
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import java.io.File

class SftpPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
    val connections: ConnectionManager
) : MethodChannel.MethodCallHandler, Disposable {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val channel = MethodChannel(messenger, Channels.SFTP)
    private val stream = EventBridge(messenger, Channels.SFTP_STREAM)
    private val queue = TransferQueue(context, connections) { stream.emit(it) }
    private val sync = FolderSync(connections, queue)

    init {
        channel.setMethodCallHandler(this)
    }

    private fun data(call: MethodCall): Map<String, Any?> =
        call.map("profile") ?: throw OnyxException("bad_args", "Argumen 'profile' wajib diisi")

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "profiles" -> scope.reply(result) { connections.listProfiles() }
            "saveProfile" -> scope.reply(result) { connections.saveProfile(data(call)) }
            "deleteProfile" -> scope.reply(result) {
                connections.deleteProfile(call.requireStr("id"))
            }
            "test" -> scope.reply(result) { connections.test(data(call)) }
            "connect" -> scope.reply(result) {
                val sessionId = connections.connect(call.requireStr("profileId"))
                val fs = connections.fs(sessionId)
                mapOf("sessionId" to sessionId, "home" to fs.home(), "protocol" to fs.protocol)
            }
            "disconnect" -> scope.reply(result) { connections.disconnect(call.requireStr("sessionId")) }
            "list" -> scope.reply(result) {
                val fs = connections.fs(call.requireStr("sessionId"))
                val path = call.str("path") ?: fs.home()
                val entries = fs.list(path)
                    .sortedWith(compareByDescending<com.onyx.terminal.sftp.RemoteEntry> { it.isDir }
                        .thenBy { it.name.lowercase() })
                mapOf("path" to path, "entries" to entries.map { it.toMap() })
            }
            "stat" -> scope.reply(result) {
                connections.fs(call.requireStr("sessionId")).stat(call.requireStr("path"))?.toMap()
            }
            "mkdir" -> scope.reply(result) {
                connections.fs(call.requireStr("sessionId")).mkdir(call.requireStr("path"))
            }
            "delete" -> scope.reply(result) {
                connections.fs(call.requireStr("sessionId"))
                    .delete(call.requireStr("path"), call.bool("recursive", true))
            }
            "rename" -> scope.reply(result) {
                connections.fs(call.requireStr("sessionId"))
                    .rename(call.requireStr("from"), call.requireStr("to"))
            }
            "chmod" -> scope.reply(result) {
                connections.fs(call.requireStr("sessionId"))
                    .chmod(call.requireStr("path"), call.int("mode", 420))
            }
            "readText" -> scope.reply(result) {
                val bytes = connections.fs(call.requireStr("sessionId"))
                    .readBytes(call.requireStr("path"), Limits.MAX_EDITABLE_BYTES)
                String(bytes, Charsets.UTF_8)
            }
            "writeText" -> scope.reply(result) {
                connections.fs(call.requireStr("sessionId"))
                    .writeBytes(call.requireStr("path"), call.requireStr("text").toByteArray(Charsets.UTF_8))
            }
            "upload" -> scope.reply(result) {
                val local = File(call.requireStr("local"))
                if (!local.exists()) throw OnyxException("not_found", "Berkas lokal tidak ditemukan")
                val sessionId = call.requireStr("sessionId")
                val remote = call.requireStr("remote")
                if (local.isDirectory) {
                    queue.enqueueUploadTree(sessionId, local, remote)
                } else {
                    queue.enqueueUpload(sessionId, local, remote.trimEnd('/') + "/" + local.name)
                    1
                }
            }
            "download" -> scope.reply(result) {
                val sessionId = call.requireStr("sessionId")
                val remote = call.requireStr("remote")
                val dir = File(call.requireStr("localDir"))
                dir.mkdirs()
                val info = connections.fs(sessionId).stat(remote)
                if (info != null && info.isDir) {
                    queue.enqueueDownloadTree(sessionId, remote, dir)
                } else {
                    val name = remote.trimEnd('/').substringAfterLast('/')
                    queue.enqueueDownload(sessionId, remote, File(dir, name), info?.size ?: 0L)
                    1
                }
            }
            "queue" -> result.success(queue.list())
            "pause" -> {
                queue.pause(call.requireStr("id"))
                result.success(null)
            }
            "resume" -> {
                queue.resume(call.requireStr("id"))
                result.success(null)
            }
            "retry" -> {
                queue.retry(call.requireStr("id"))
                result.success(null)
            }
            "cancel" -> {
                queue.cancel(call.requireStr("id"))
                result.success(null)
            }
            "cancelAll" -> {
                queue.cancelAll()
                result.success(null)
            }
            "clearFinished" -> {
                queue.clearFinished()
                result.success(null)
            }
            "setConcurrency" -> {
                queue.concurrency = call.int("value", 2).coerceIn(1, 6)
                result.success(null)
            }
            "compare" -> scope.reply(result) {
                sync.compare(
                    call.requireStr("sessionId"),
                    File(call.requireStr("local")),
                    call.requireStr("remote")
                )
            }
            "sync" -> scope.reply(result) {
                sync.sync(
                    call.requireStr("sessionId"),
                    File(call.requireStr("local")),
                    call.requireStr("remote"),
                    call.str("mode") ?: "up"
                )
            }
            "keys" -> scope.reply(result) { connections.keys.list().map { it.toMap() } }
            "generateKey" -> scope.reply(result) {
                connections.keys.generate(call.requireStr("type"), call.requireStr("name")).toMap()
            }
            "importKey" -> scope.reply(result) {
                connections.keys.import(
                    call.requireStr("name"),
                    call.requireStr("pem"),
                    call.str("passphrase")
                ).toMap()
            }
            "deleteKey" -> scope.reply(result) { connections.keys.delete(call.requireStr("id")) }
            "forgetHost" -> scope.reply(result) {
                connections.forgetHost(call.requireStr("host"), call.int("port", 22))
            }
            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        channel.setMethodCallHandler(null)
        stream.dispose()
        queue.dispose()
        connections.disconnectAll()
        scope.cancel()
    }
}
