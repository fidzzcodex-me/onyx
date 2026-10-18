package com.onyx.terminal.filesystem

import android.content.Context
import android.system.Os
import android.webkit.MimeTypeMap
import com.onyx.terminal.util.Limits
import com.onyx.terminal.util.OnyxException
import com.onyx.terminal.util.modeToString
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.LinkOption
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class OperationHandle(val id: String, val kind: String) {
    @Volatile
    var cancelled = false

    @Volatile
    var total = 0L

    @Volatile
    var done = 0L

    @Volatile
    var current = ""
}

class FileManager(private val context: Context) {
    val trashDir: File = File(context.filesDir, "trash")
    private val operations = ConcurrentHashMap<String, OperationHandle>()

    fun newOperation(kind: String): OperationHandle {
        val handle = OperationHandle(UUID.randomUUID().toString(), kind)
        operations[handle.id] = handle
        return handle
    }

    fun finish(handle: OperationHandle) {
        operations.remove(handle.id)
    }

    fun cancel(id: String) {
        operations[id]?.cancelled = true
    }

    fun mimeOf(file: File): String {
        val ext = file.extension.lowercase()
        if (ext.isEmpty()) return "application/octet-stream"
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: when (ext) {
            "md", "markdown" -> "text/markdown"
            "kt", "kts", "java", "dart", "go", "rs", "py", "rb", "sh", "bash", "zsh", "c", "h", "cpp", "hpp",
            "cs", "swift", "lua", "toml", "ini", "conf", "cfg", "env", "log", "gradle", "properties",
            "yaml", "yml", "ts", "tsx", "jsx", "vue", "sql", "dockerfile", "makefile" -> "text/plain"
            "7z" -> "application/x-7z-compressed"
            "rar" -> "application/vnd.rar"
            "mkv" -> "video/x-matroska"
            "flac" -> "audio/flac"
            "opus" -> "audio/opus"
            else -> "application/octet-stream"
        }
    }

    fun describe(file: File): Map<String, Any?> {
        val isLink = try {
            Files.isSymbolicLink(file.toPath())
        } catch (_: Exception) {
            false
        }
        val isDir = file.isDirectory
        val modeBits = try {
            Os.stat(file.absolutePath).st_mode and 0xfff
        } catch (_: Exception) {
            if (file.canWrite()) 0x1a4 else 0x124
        }
        return mapOf(
            "name" to file.name,
            "path" to file.absolutePath,
            "isDir" to isDir,
            "size" to if (isDir) 0L else file.length(),
            "modified" to file.lastModified(),
            "mode" to modeToString(modeBits, isDir, isLink),
            "isLink" to isLink,
            "mime" to if (isDir) "inode/directory" else mimeOf(file),
            "readable" to file.canRead(),
            "writable" to file.canWrite(),
            "hidden" to file.name.startsWith(".")
        )
    }

    fun list(path: String, showHidden: Boolean, sort: String, ascending: Boolean): Map<String, Any?> {
        val dir = File(path)
        if (!dir.exists()) throw OnyxException("not_found", "Folder tidak ditemukan: $path")
        if (!dir.isDirectory) throw OnyxException("not_dir", "Bukan folder: $path")
        val children = dir.listFiles()
            ?: throw OnyxException("denied", "Tidak ada izin membaca folder ini")
        val visible = children.filter { showHidden || !it.name.startsWith(".") }
        val comparator: Comparator<File> = when (sort) {
            "size" -> compareBy<File> { if (it.isDirectory) -1L else it.length() }
            "date" -> compareBy<File> { it.lastModified() }
            "type" -> compareBy<File> { it.extension.lowercase() }.thenBy { it.name.lowercase() }
            else -> compareBy<File> { it.name.lowercase() }
        }
        val ordered = visible.sortedWith(if (ascending) comparator else comparator.reversed())
        val folders = ordered.filter { it.isDirectory }
        val files = ordered.filter { !it.isDirectory }
        return mapOf(
            "path" to dir.absolutePath,
            "parent" to dir.parentFile?.absolutePath,
            "hiddenCount" to children.count { it.name.startsWith(".") },
            "entries" to (folders + files).map { describe(it) }
        )
    }

    fun stat(path: String): Map<String, Any?>? {
        val file = File(path)
        return if (file.exists() || isBrokenLink(file)) describe(file) else null
    }

    private fun isBrokenLink(file: File): Boolean = try {
        Files.isSymbolicLink(file.toPath())
    } catch (_: Exception) {
        false
    }

    fun mkdir(path: String) {
        val dir = File(path)
        if (dir.exists()) throw OnyxException("exists", "Sudah ada: ${dir.name}")
        if (!dir.mkdirs()) throw OnyxException("denied", "Tidak dapat membuat folder ${dir.name}")
    }

    fun createFile(path: String) {
        val file = File(path)
        if (file.exists()) throw OnyxException("exists", "Sudah ada: ${file.name}")
        file.parentFile?.mkdirs()
        if (!file.createNewFile()) throw OnyxException("denied", "Tidak dapat membuat berkas ${file.name}")
    }

    fun rename(from: String, to: String) {
        val source = File(from)
        val target = File(to)
        if (!source.exists() && !isBrokenLink(source)) throw OnyxException("not_found", "Sumber tidak ditemukan")
        if (target.exists()) throw OnyxException("exists", "Nama sudah dipakai: ${target.name}")
        if (!source.renameTo(target)) {
            copyTree(source, target, OperationHandle("rename", "rename"), "rename")
            deleteTree(source)
        }
    }

    fun uniqueName(target: File): File {
        if (!target.exists()) return target
        val base = target.nameWithoutExtension
        val ext = target.extension
        var index = 1
        while (true) {
            val name = if (ext.isEmpty()) "$base ($index)" else "$base ($index).$ext"
            val candidate = File(target.parentFile, name)
            if (!candidate.exists()) return candidate
            index++
        }
    }

    fun measure(file: File, limit: Long = Long.MAX_VALUE): Long {
        if (!file.isDirectory) return file.length()
        var sum = 0L
        val stack = ArrayDeque<File>()
        stack.add(file)
        while (stack.isNotEmpty() && sum < limit) {
            val current = stack.removeLast()
            val children = current.listFiles() ?: continue
            for (child in children) {
                val link = try {
                    Files.isSymbolicLink(child.toPath())
                } catch (_: Exception) {
                    false
                }
                if (link) continue
                if (child.isDirectory) stack.add(child) else sum += child.length()
            }
        }
        return sum
    }

    fun copy(
        sources: List<String>,
        destDir: String,
        move: Boolean,
        conflict: String,
        handle: OperationHandle,
        onProgress: () -> Unit
    ): Int {
        val dest = File(destDir)
        if (!dest.isDirectory) throw OnyxException("not_dir", "Tujuan bukan folder")
        handle.total = sources.sumOf { measure(File(it)).coerceAtLeast(1L) }
        var count = 0
        for (path in sources) {
            if (handle.cancelled) break
            val source = File(path)
            if (!source.exists()) continue
            val canonicalSource = source.canonicalPath
            val canonicalDest = dest.canonicalPath
            if (source.isDirectory && (canonicalDest == canonicalSource ||
                    canonicalDest.startsWith(canonicalSource + File.separator))) {
                throw OnyxException("recursive", "Folder tidak dapat disalin ke dalam dirinya sendiri")
            }
            var target = File(dest, source.name)
            if (target.exists()) {
                if (target.canonicalPath == canonicalSource) {
                    if (move) continue
                    target = uniqueName(target)
                } else {
                    when (conflict) {
                        "skip" -> continue
                        "overwrite" -> deleteTree(target)
                        else -> target = uniqueName(target)
                    }
                }
            }
            if (move && source.renameTo(target)) {
                handle.done += measure(target).coerceAtLeast(1L)
                onProgress()
                count++
                continue
            }
            copyTree(source, target, handle, "copy", onProgress)
            if (move && !handle.cancelled) deleteTree(source)
            count++
        }
        return count
    }

    private fun copyTree(
        source: File,
        target: File,
        handle: OperationHandle,
        kind: String,
        onProgress: () -> Unit = {}
    ) {
        if (handle.cancelled) return
        val link = try {
            Files.isSymbolicLink(source.toPath())
        } catch (_: Exception) {
            false
        }
        if (link) {
            try {
                val destination = Files.readSymbolicLink(source.toPath())
                Files.createSymbolicLink(target.toPath(), destination)
            } catch (_: Exception) {
            }
            return
        }
        if (source.isDirectory) {
            if (!target.exists() && !target.mkdirs()) throw OnyxException("denied", "Tidak dapat membuat ${target.name}")
            val children = source.listFiles() ?: return
            for (child in children) copyTree(child, File(target, child.name), handle, kind, onProgress)
            try {
                Os.chmod(target.absolutePath, Os.stat(source.absolutePath).st_mode and 0xfff)
            } catch (_: Exception) {
            }
            return
        }
        handle.current = source.name
        FileInputStream(source).use { input ->
            FileOutputStream(target).use { output ->
                val buffer = ByteArray(128 * 1024)
                var lastEmit = 0L
                while (true) {
                    if (handle.cancelled) {
                        output.close()
                        target.delete()
                        return
                    }
                    val read = input.read(buffer)
                    if (read < 0) break
                    output.write(buffer, 0, read)
                    handle.done += read
                    val now = System.currentTimeMillis()
                    if (now - lastEmit > 200) {
                        lastEmit = now
                        onProgress()
                    }
                }
            }
        }
        target.setLastModified(source.lastModified())
        try {
            Os.chmod(target.absolutePath, Os.stat(source.absolutePath).st_mode and 0xfff)
        } catch (_: Exception) {
        }
        if (source.length() == 0L) handle.done += 1
    }

    fun deleteTree(file: File): Boolean {
        val link = try {
            Files.isSymbolicLink(file.toPath())
        } catch (_: Exception) {
            false
        }
        if (!link && file.isDirectory) {
            file.listFiles()?.forEach { deleteTree(it) }
        }
        return file.delete()
    }

    fun delete(paths: List<String>, toTrash: Boolean): Int {
        var count = 0
        for (path in paths) {
            val file = File(path)
            if (!file.exists() && !isBrokenLink(file)) continue
            if (toTrash && !file.absolutePath.startsWith(trashDir.absolutePath)) {
                moveToTrash(file)
            } else if (!deleteTree(file)) {
                throw OnyxException("denied", "Tidak dapat menghapus ${file.name}")
            }
            count++
        }
        return count
    }

    private fun moveToTrash(file: File) {
        trashDir.mkdirs()
        val id = UUID.randomUUID().toString()
        val slot = File(trashDir, id)
        slot.mkdirs()
        val payload = File(slot, file.name)
        val handle = OperationHandle(id, "trash")
        if (!file.renameTo(payload)) {
            copyTree(file, payload, handle, "trash")
            if (!deleteTree(file)) throw OnyxException("denied", "Tidak dapat memindahkan ${file.name} ke sampah")
        }
        File(slot, ".origin").writeText(file.absolutePath + "\n" + System.currentTimeMillis())
    }

    fun trashList(): List<Map<String, Any?>> {
        val slots = trashDir.listFiles() ?: return emptyList()
        val out = ArrayList<Map<String, Any?>>()
        for (slot in slots) {
            val origin = File(slot, ".origin")
            val payload = slot.listFiles()?.firstOrNull { it.name != ".origin" } ?: continue
            val lines = if (origin.exists()) origin.readLines() else emptyList()
            out.add(
                mapOf(
                    "id" to slot.name,
                    "name" to payload.name,
                    "originalPath" to (lines.getOrNull(0) ?: ""),
                    "deletedAt" to (lines.getOrNull(1)?.toLongOrNull() ?: slot.lastModified()),
                    "isDir" to payload.isDirectory,
                    "size" to measure(payload)
                )
            )
        }
        return out.sortedByDescending { it["deletedAt"] as Long }
    }

    fun trashRestore(id: String): String {
        val slot = File(trashDir, id)
        val payload = slot.listFiles()?.firstOrNull { it.name != ".origin" }
            ?: throw OnyxException("not_found", "Item sampah tidak ditemukan")
        val origin = File(slot, ".origin").takeIf { it.exists() }?.readLines()?.firstOrNull()
            ?: throw OnyxException("no_origin", "Lokasi asal tidak diketahui")
        val target = uniqueName(File(origin))
        target.parentFile?.mkdirs()
        if (!payload.renameTo(target)) {
            copyTree(payload, target, OperationHandle(id, "restore"), "restore")
            deleteTree(payload)
        }
        deleteTree(slot)
        return target.absolutePath
    }

    fun trashEmpty(id: String?) {
        if (id != null) {
            deleteTree(File(trashDir, id))
        } else {
            trashDir.listFiles()?.forEach { deleteTree(it) }
        }
    }

    fun chmod(path: String, mode: Int, recursive: Boolean) {
        val file = File(path)
        if (!file.exists()) throw OnyxException("not_found", "Berkas tidak ditemukan")
        fun apply(target: File) {
            try {
                Os.chmod(target.absolutePath, mode and 0xfff)
            } catch (error: Exception) {
                throw OnyxException("denied", "Tidak dapat mengubah izin ${target.name}: ${error.message}")
            }
        }
        apply(file)
        if (recursive && file.isDirectory) {
            file.walkTopDown().filter { it != file }.forEach { apply(it) }
        }
    }

    fun properties(path: String): Map<String, Any?> {
        val file = File(path)
        if (!file.exists()) throw OnyxException("not_found", "Berkas tidak ditemukan")
        val base = HashMap<String, Any?>(describe(file))
        var files = 0
        var folders = 0
        if (file.isDirectory) {
            val stack = ArrayDeque<File>()
            stack.add(file)
            var visited = 0
            while (stack.isNotEmpty() && visited < 200_000) {
                val current = stack.removeLast()
                val kids = current.listFiles() ?: continue
                for (kid in kids) {
                    visited++
                    if (kid.isDirectory && !Files.isSymbolicLink(kid.toPath())) {
                        folders++
                        stack.add(kid)
                    } else {
                        files++
                    }
                }
            }
            base["size"] = measure(file)
        }
        base["files"] = files
        base["folders"] = folders
        base["owner"] = try {
            Os.stat(file.absolutePath).st_uid
        } catch (_: Exception) {
            -1
        }
        base["octal"] = try {
            Integer.toOctalString(Os.stat(file.absolutePath).st_mode and 0xfff)
        } catch (_: Exception) {
            ""
        }
        base["canonical"] = try {
            file.canonicalPath
        } catch (_: Exception) {
            file.absolutePath
        }
        base["linkTarget"] = try {
            if (Files.isSymbolicLink(file.toPath())) Files.readSymbolicLink(file.toPath()).toString() else null
        } catch (_: Exception) {
            null
        }
        return base
    }

    fun search(
        root: String,
        query: String,
        regex: Boolean,
        caseSensitive: Boolean,
        includeHidden: Boolean,
        handle: OperationHandle,
        limit: Int = Limits.MAX_SEARCH_RESULTS
    ): List<Map<String, Any?>> {
        val base = File(root)
        if (!base.isDirectory) throw OnyxException("not_dir", "Folder pencarian tidak valid")
        val matcher = buildMatcher(query, regex, caseSensitive)
        val results = ArrayList<Map<String, Any?>>()
        val stack = ArrayDeque<File>()
        stack.add(base)
        while (stack.isNotEmpty() && results.size < limit && !handle.cancelled) {
            val dir = stack.removeLast()
            val kids = dir.listFiles() ?: continue
            for (kid in kids) {
                if (!includeHidden && kid.name.startsWith(".")) continue
                if (matcher(kid.name)) {
                    results.add(describe(kid))
                    if (results.size >= limit) break
                }
                val link = try {
                    Files.isSymbolicLink(kid.toPath())
                } catch (_: Exception) {
                    false
                }
                if (kid.isDirectory && !link) stack.add(kid)
            }
        }
        return results
    }

    private fun buildMatcher(query: String, regex: Boolean, caseSensitive: Boolean): (String) -> Boolean {
        if (regex) {
            val options = if (caseSensitive) emptySet() else setOf(RegexOption.IGNORE_CASE)
            val pattern = try {
                Regex(query, options)
            } catch (error: Exception) {
                throw OnyxException("bad_regex", "Pola regex tidak valid: ${error.message}")
            }
            return { name -> pattern.containsMatchIn(name) }
        }
        val needle = if (caseSensitive) query else query.lowercase()
        return { name -> (if (caseSensitive) name else name.lowercase()).contains(needle) }
    }

    fun duplicates(root: String, handle: OperationHandle, minSize: Long): List<Map<String, Any?>> {
        val bySize = HashMap<Long, MutableList<File>>()
        val stack = ArrayDeque<File>()
        stack.add(File(root))
        var visited = 0
        while (stack.isNotEmpty() && visited < 300_000 && !handle.cancelled) {
            val dir = stack.removeLast()
            val kids = dir.listFiles() ?: continue
            for (kid in kids) {
                visited++
                val link = try {
                    Files.isSymbolicLink(kid.toPath())
                } catch (_: Exception) {
                    false
                }
                if (link) continue
                if (kid.isDirectory) {
                    stack.add(kid)
                } else if (kid.length() >= minSize) {
                    bySize.getOrPut(kid.length()) { ArrayList() }.add(kid)
                }
            }
        }
        val out = ArrayList<Map<String, Any?>>()
        val digestName = "SHA-256"
        for ((size, group) in bySize) {
            if (group.size < 2 || handle.cancelled) continue
            val byHash = HashMap<String, MutableList<File>>()
            for (file in group) {
                val hash = try {
                    val md = java.security.MessageDigest.getInstance(digestName)
                    FileInputStream(file).use { input ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val read = input.read(buffer)
                            if (read < 0) break
                            md.update(buffer, 0, read)
                        }
                    }
                    md.digest().joinToString("") { "%02x".format(it) }
                } catch (_: Exception) {
                    continue
                }
                byHash.getOrPut(hash) { ArrayList() }.add(file)
            }
            for ((hash, same) in byHash) {
                if (same.size > 1) {
                    out.add(mapOf("hash" to hash, "size" to size, "paths" to same.map { it.absolutePath }))
                }
            }
        }
        return out.sortedByDescending { (it["size"] as Long) * ((it["paths"] as List<*>).size - 1) }
    }

    fun checksum(path: String, algorithm: String): String {
        val name = when (algorithm.lowercase()) {
            "md5" -> "MD5"
            "sha1" -> "SHA-1"
            "sha256" -> "SHA-256"
            "sha512" -> "SHA-512"
            else -> throw OnyxException("bad_algorithm", "Algoritma tidak didukung: $algorithm")
        }
        val file = File(path)
        if (!file.isFile) throw OnyxException("not_file", "Hanya berkas yang dapat dihitung checksum-nya")
        val md = java.security.MessageDigest.getInstance(name)
        FileInputStream(file).use { input ->
            val buffer = ByteArray(128 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                md.update(buffer, 0, read)
            }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }

    fun symlink(target: String, linkPath: String) {
        try {
            Os.symlink(target, linkPath)
        } catch (error: Exception) {
            throw OnyxException("denied", "Tidak dapat membuat tautan: ${error.message}")
        }
    }

    fun exists(path: String): Boolean = File(path).exists() || isBrokenLink(File(path))

    fun isSymlink(path: String): Boolean = isBrokenLink(File(path))
}
