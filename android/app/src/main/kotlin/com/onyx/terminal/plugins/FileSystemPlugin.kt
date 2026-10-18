package com.onyx.terminal.plugins

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import com.onyx.terminal.db.AppDatabase
import com.onyx.terminal.db.BookmarkDao
import com.onyx.terminal.filesystem.ArchiveEngine
import com.onyx.terminal.filesystem.FileManager
import com.onyx.terminal.filesystem.FileWatcher
import com.onyx.terminal.filesystem.OperationHandle
import com.onyx.terminal.filesystem.StorageAccess
import com.onyx.terminal.util.Channels
import com.onyx.terminal.util.Disposable
import com.onyx.terminal.util.EventBridge
import com.onyx.terminal.util.Limits
import com.onyx.terminal.util.OnyxException
import com.onyx.terminal.util.bool
import com.onyx.terminal.util.int
import com.onyx.terminal.util.long
import com.onyx.terminal.util.reply
import com.onyx.terminal.util.requireStr
import com.onyx.terminal.util.str
import com.onyx.terminal.util.strList
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID

class FileSystemPlugin(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, Disposable {
    val files = FileManager(context)
    private val storage = StorageAccess(context)
    private val archives = ArchiveEngine()
    private val bookmarks = BookmarkDao(AppDatabase.get(context))
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val channel = MethodChannel(messenger, Channels.FS)
    private val stream = EventBridge(messenger, Channels.FS_EVENTS)
    private val watcher = FileWatcher { path -> stream.emit(mapOf("type" to "change", "path" to path)) }

    init {
        channel.setMethodCallHandler(this)
    }

    private fun emitOp(handle: OperationHandle, state: String, extra: Map<String, Any?> = emptyMap()) {
        val event = HashMap<String, Any?>()
        event["type"] = "op"
        event["id"] = handle.id
        event["kind"] = handle.kind
        event["state"] = state
        event["done"] = handle.done
        event["total"] = handle.total
        event["current"] = handle.current
        event.putAll(extra)
        stream.emit(event)
    }

    private fun background(kind: String, result: MethodChannel.Result, work: (OperationHandle) -> Map<String, Any?>) {
        val handle = files.newOperation(kind)
        result.success(handle.id)
        scope.launch {
            emitOp(handle, "running")
            try {
                val extra = work(handle)
                emitOp(handle, if (handle.cancelled) "canceled" else "done", extra)
            } catch (error: OnyxException) {
                emitOp(handle, "error", mapOf("error" to error.message, "code" to error.code))
            } catch (error: Throwable) {
                emitOp(handle, "error", mapOf("error" to (error.message ?: error.javaClass.simpleName)))
            } finally {
                files.finish(handle)
            }
        }
    }

    private fun openExternal(path: String, mime: String?, chooser: Boolean, send: Boolean) {
        val file = File(path)
        if (!file.exists()) throw OnyxException("not_found", "Berkas tidak ditemukan")
        val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", file)
        val type = mime ?: files.mimeOf(file)
        val base = if (send) {
            Intent(Intent.ACTION_SEND).apply {
                this.type = type
                putExtra(Intent.EXTRA_STREAM, uri)
            }
        } else {
            Intent(Intent.ACTION_VIEW).apply { setDataAndType(uri, type) }
        }
        base.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val intent = if (chooser) Intent.createChooser(base, file.name) else base
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            throw OnyxException("no_app", "Tidak ada aplikasi yang dapat membuka berkas ini")
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "roots" -> scope.reply(result) { storage.roots() }
            "hasAccess" -> result.success(storage.hasAllFilesAccess())
            "openAccessSettings" -> {
                storage.openAllFilesSettings()
                result.success(null)
            }
            "usage" -> scope.reply(result) { storage.usage(call.requireStr("path")) }
            "list" -> scope.reply(result) {
                files.list(
                    call.requireStr("path"),
                    call.bool("showHidden", false),
                    call.str("sort") ?: "name",
                    call.bool("ascending", true)
                )
            }
            "stat" -> scope.reply(result) { files.stat(call.requireStr("path")) }
            "exists" -> scope.reply(result) { files.exists(call.requireStr("path")) }
            "mkdir" -> scope.reply(result) { files.mkdir(call.requireStr("path")) }
            "createFile" -> scope.reply(result) { files.createFile(call.requireStr("path")) }
            "rename" -> scope.reply(result) { files.rename(call.requireStr("from"), call.requireStr("to")) }
            "delete" -> scope.reply(result) {
                files.delete(call.strList("paths"), call.bool("trash", true))
            }
            "copy" -> {
                val sources = call.strList("sources")
                val dest = call.requireStr("dest")
                val move = call.bool("move", false)
                val conflict = call.str("conflict") ?: "rename"
                background(if (move) "move" else "copy", result) { handle ->
                    val count = files.copy(sources, dest, move, conflict, handle) { emitOp(handle, "running") }
                    mapOf("count" to count)
                }
            }
            "cancelOp" -> {
                files.cancel(call.requireStr("id"))
                result.success(null)
            }
            "properties" -> scope.reply(result) { files.properties(call.requireStr("path")) }
            "chmod" -> scope.reply(result) {
                files.chmod(call.requireStr("path"), call.int("mode", 420), call.bool("recursive", false))
            }
            "symlink" -> scope.reply(result) {
                files.symlink(call.requireStr("target"), call.requireStr("link"))
            }
            "checksum" -> scope.reply(result) {
                files.checksum(call.requireStr("path"), call.str("algorithm") ?: "sha256")
            }
            "search" -> {
                val root = call.requireStr("root")
                val query = call.requireStr("query")
                val regex = call.bool("regex", false)
                val caseSensitive = call.bool("caseSensitive", false)
                val hidden = call.bool("hidden", false)
                background("search", result) { handle ->
                    val found = files.search(root, query, regex, caseSensitive, hidden, handle)
                    mapOf("results" to found, "truncated" to (found.size >= Limits.MAX_SEARCH_RESULTS))
                }
            }
            "duplicates" -> {
                val root = call.requireStr("root")
                val minSize = call.long("minSize", 1024L)
                background("duplicates", result) { handle ->
                    mapOf("groups" to files.duplicates(root, handle, minSize))
                }
            }
            "trashList" -> scope.reply(result) { files.trashList() }
            "trashRestore" -> scope.reply(result) { files.trashRestore(call.requireStr("id")) }
            "trashEmpty" -> scope.reply(result) { files.trashEmpty(call.str("id")) }
            "bookmarks" -> scope.reply(result) { bookmarks.all(call.str("type")) }
            "addBookmark" -> scope.reply(result) {
                val type = call.requireStr("type")
                val value = call.requireStr("value")
                val existing = bookmarks.findByValue(type, value)
                val id = (existing?.get("id") as? String) ?: UUID.randomUUID().toString()
                bookmarks.insert(id, type, call.str("title") ?: File(value).name.ifEmpty { value }, value, call.str("extra"))
                id
            }
            "removeBookmark" -> scope.reply(result) { bookmarks.delete(call.requireStr("id")) }
            "watch" -> {
                watcher.watch(call.str("path"))
                result.success(null)
            }
            "open" -> scope.reply(result) {
                openExternal(call.requireStr("path"), call.str("mime"), call.bool("chooser", false), false)
            }
            "share" -> scope.reply(result) {
                openExternal(call.requireStr("path"), call.str("mime"), true, true)
            }
            "archiveSupported" -> result.success(archives.isSupported(File(call.requireStr("path"))))
            "archiveList" -> scope.reply(result) {
                mapOf(
                    "kind" to archives.kind(File(call.requireStr("path"))),
                    "entries" to archives.list(File(call.requireStr("path")), 20_000)
                )
            }
            "archiveRead" -> scope.reply(result) {
                archives.readEntry(
                    File(call.requireStr("path")),
                    call.requireStr("entry"),
                    Limits.MAX_PREVIEW_BYTES * 4
                )
            }
            "extract" -> {
                val archive = File(call.requireStr("path"))
                val dest = File(call.requireStr("dest"))
                val only = call.strList("only").toSet().takeIf { it.isNotEmpty() }
                background("extract", result) { handle ->
                    handle.total = archive.length().coerceAtLeast(1L) * 3
                    var last = 0L
                    val count = archives.extract(archive, dest, only, { done, current ->
                        handle.done = done
                        handle.current = current
                        val now = System.currentTimeMillis()
                        if (now - last > 200) {
                            last = now
                            emitOp(handle, "running")
                        }
                    }) { handle.cancelled }
                    mapOf("count" to count, "dest" to dest.absolutePath)
                }
            }
            "compress" -> {
                val sources = call.strList("sources").map { File(it) }
                val out = File(call.requireStr("output"))
                val format = call.str("format") ?: "zip"
                background("compress", result) { handle ->
                    handle.total = sources.sumOf { files.measure(it) }.coerceAtLeast(1L)
                    var last = 0L
                    val count = archives.create(sources, out, format, { done, current ->
                        handle.done = done
                        handle.current = current
                        val now = System.currentTimeMillis()
                        if (now - last > 200) {
                            last = now
                            emitOp(handle, "running")
                        }
                    }) { handle.cancelled }
                    mapOf("count" to count, "output" to out.absolutePath)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        watcher.stop()
        channel.setMethodCallHandler(null)
        stream.dispose()
        scope.cancel()
    }
}
