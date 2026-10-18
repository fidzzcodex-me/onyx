package com.onyx.terminal.filesystem

import com.github.junrar.Archive
import com.onyx.terminal.util.OnyxException
import org.apache.commons.compress.archivers.ArchiveEntry
import org.apache.commons.compress.archivers.sevenz.SevenZFile
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.archivers.tar.TarArchiveOutputStream
import org.apache.commons.compress.archivers.zip.ZipArchiveEntry
import org.apache.commons.compress.archivers.zip.ZipArchiveOutputStream
import org.apache.commons.compress.archivers.zip.ZipFile
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorOutputStream
import org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream
import org.apache.commons.compress.compressors.gzip.GzipCompressorOutputStream
import org.apache.commons.compress.compressors.xz.XZCompressorInputStream
import org.apache.commons.compress.compressors.xz.XZCompressorOutputStream
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream

class ArchiveEngine {
    fun kind(file: File): String? {
        val name = file.name.lowercase()
        return when {
            name.endsWith(".zip") || name.endsWith(".apk") || name.endsWith(".jar") ||
                name.endsWith(".aar") || name.endsWith(".epub") -> "zip"
            name.endsWith(".tar.gz") || name.endsWith(".tgz") -> "tgz"
            name.endsWith(".tar.bz2") || name.endsWith(".tbz2") || name.endsWith(".tbz") -> "tbz2"
            name.endsWith(".tar.xz") || name.endsWith(".txz") -> "txz"
            name.endsWith(".tar") -> "tar"
            name.endsWith(".7z") -> "7z"
            name.endsWith(".rar") -> "rar"
            name.endsWith(".gz") -> "gz"
            name.endsWith(".bz2") -> "bz2"
            name.endsWith(".xz") -> "xz"
            else -> null
        }
    }

    fun isSupported(file: File): Boolean = kind(file) != null

    private fun safeTarget(root: File, name: String): File {
        val cleaned = name.replace('\\', '/').trimStart('/')
        val target = File(root, cleaned)
        val rootPath = root.canonicalPath
        val targetPath = target.canonicalPath
        if (targetPath != rootPath && !targetPath.startsWith(rootPath + File.separator)) {
            throw OnyxException("zip_slip", "Arsip berisi jalur berbahaya: $name")
        }
        return target
    }

    private fun tarStream(kind: String, input: InputStream): TarArchiveInputStream {
        val buffered = BufferedInputStream(input, 128 * 1024)
        val decoded: InputStream = when (kind) {
            "tgz" -> GzipCompressorInputStream(buffered)
            "tbz2" -> BZip2CompressorInputStream(buffered)
            "txz" -> XZCompressorInputStream(buffered)
            else -> buffered
        }
        return TarArchiveInputStream(decoded)
    }

    fun list(file: File, limit: Int): List<Map<String, Any?>> {
        val kind = kind(file) ?: throw OnyxException("unsupported", "Format arsip tidak didukung")
        val out = ArrayList<Map<String, Any?>>()
        fun add(name: String, dir: Boolean, size: Long, modified: Long, packed: Long) {
            if (out.size < limit) {
                out.add(
                    mapOf(
                        "name" to name.trimEnd('/'),
                        "isDir" to dir,
                        "size" to size,
                        "packed" to packed,
                        "modified" to modified
                    )
                )
            }
        }
        when (kind) {
            "zip" -> ZipFile.builder().setFile(file).get().use { zip ->
                val entries = zip.entries
                while (entries.hasMoreElements()) {
                    val e = entries.nextElement()
                    add(e.name, e.isDirectory, e.size, e.time, e.compressedSize)
                }
            }
            "7z" -> SevenZFile.builder().setFile(file).get().use { z ->
                for (e in z.entries) add(e.name, e.isDirectory, e.size, (if (e.hasLastModifiedDate) e.lastModifiedDate.time else 0L), -1L)
            }
            "rar" -> Archive(file).use { rar ->
                for (h in rar.fileHeaders) {
                    add(h.fileName, h.isDirectory, h.fullUnpackSize, h.mTime?.time ?: 0L, h.fullPackSize)
                }
            }
            "gz", "bz2", "xz" -> add(singleName(file), false, -1L, file.lastModified(), file.length())
            else -> FileInputStream(file).use { raw ->
                tarStream(kind, raw).use { tar ->
                    var entry: TarArchiveEntry? = tar.nextEntry
                    while (entry != null && out.size < limit) {
                        add(entry.name, entry.isDirectory, entry.size, entry.modTime?.time ?: 0L, -1L)
                        entry = tar.nextEntry
                    }
                }
            }
        }
        return out
    }

    private fun singleName(file: File): String = file.name.substringBeforeLast('.')

    fun extract(
        file: File,
        dest: File,
        only: Set<String>?,
        progress: (done: Long, current: String) -> Unit,
        cancelled: () -> Boolean
    ): Int {
        val kind = kind(file) ?: throw OnyxException("unsupported", "Format arsip tidak didukung")
        dest.mkdirs()
        var count = 0
        var done = 0L
        fun wanted(name: String): Boolean {
            if (only == null) return true
            val clean = name.trimEnd('/')
            return only.any { clean == it || clean.startsWith("$it/") }
        }
        fun write(name: String, dir: Boolean, modified: Long, stream: InputStream?) {
            val target = safeTarget(dest, name)
            if (dir) {
                target.mkdirs()
                return
            }
            target.parentFile?.mkdirs()
            FileOutputStream(target).use { output ->
                if (stream != null) {
                    val buffer = ByteArray(128 * 1024)
                    while (true) {
                        if (cancelled()) return
                        val read = stream.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        done += read
                        progress(done, name)
                    }
                }
            }
            if (modified > 0) target.setLastModified(modified)
            count++
        }
        when (kind) {
            "zip" -> ZipFile.builder().setFile(file).get().use { zip ->
                val entries = zip.entries
                while (entries.hasMoreElements() && !cancelled()) {
                    val e: ZipArchiveEntry = entries.nextElement()
                    if (!wanted(e.name)) continue
                    if (e.isDirectory) {
                        write(e.name, true, e.time, null)
                    } else {
                        zip.getInputStream(e).use { write(e.name, false, e.time, it) }
                    }
                }
            }
            "7z" -> SevenZFile.builder().setFile(file).get().use { z ->
                var e = z.nextEntry
                while (e != null && !cancelled()) {
                    if (wanted(e.name)) {
                        if (e.isDirectory) {
                            write(e.name, true, 0L, null)
                        } else {
                            val sevenZ = z
                            val stream = object : InputStream() {
                                override fun read(): Int = sevenZ.read()
                                override fun read(b: ByteArray, off: Int, len: Int): Int = sevenZ.read(b, off, len)
                            }
                            write(e.name, false, (if (e.hasLastModifiedDate) e.lastModifiedDate.time else 0L), stream)
                        }
                    }
                    e = z.nextEntry
                }
            }
            "rar" -> Archive(file).use { rar ->
                for (h in rar.fileHeaders) {
                    if (cancelled()) break
                    if (!wanted(h.fileName)) continue
                    if (h.isDirectory) {
                        write(h.fileName, true, 0L, null)
                    } else {
                        val target = safeTarget(dest, h.fileName)
                        target.parentFile?.mkdirs()
                        FileOutputStream(target).use { rar.extractFile(h, it) }
                        h.mTime?.time?.let { target.setLastModified(it) }
                        done += target.length()
                        progress(done, h.fileName)
                        count++
                    }
                }
            }
            "gz", "bz2", "xz" -> FileInputStream(file).use { raw ->
                val buffered = BufferedInputStream(raw)
                val decoded: InputStream = when (kind) {
                    "gz" -> GzipCompressorInputStream(buffered)
                    "bz2" -> BZip2CompressorInputStream(buffered)
                    else -> XZCompressorInputStream(buffered)
                }
                decoded.use { write(singleName(file), false, file.lastModified(), it) }
            }
            else -> FileInputStream(file).use { raw ->
                tarStream(kind, raw).use { tar ->
                    var entry: ArchiveEntry? = tar.nextEntry
                    while (entry != null && !cancelled()) {
                        if (wanted(entry.name)) {
                            if (entry.isDirectory) {
                                write(entry.name, true, 0L, null)
                            } else {
                                write(entry.name, false, entry.lastModifiedDate?.time ?: 0L, tar)
                            }
                        }
                        entry = tar.nextEntry
                    }
                }
            }
        }
        return count
    }

    fun create(
        sources: List<File>,
        out: File,
        format: String,
        progress: (done: Long, current: String) -> Unit,
        cancelled: () -> Boolean
    ): Int {
        out.parentFile?.mkdirs()
        var count = 0
        var done = 0L
        val files = ArrayList<Pair<File, String>>()
        fun collect(file: File, prefix: String) {
            val name = if (prefix.isEmpty()) file.name else "$prefix/${file.name}"
            if (file.isDirectory) {
                files.add(file to "$name/")
                file.listFiles()?.sortedBy { it.name }?.forEach { collect(it, name) }
            } else if (file.isFile) {
                files.add(file to name)
            }
        }
        sources.forEach { collect(it, "") }
        fun copyInto(file: File, output: OutputStream, name: String) {
            FileInputStream(file).use { input ->
                val buffer = ByteArray(128 * 1024)
                while (true) {
                    if (cancelled()) return
                    val read = input.read(buffer)
                    if (read < 0) break
                    output.write(buffer, 0, read)
                    done += read
                    progress(done, name)
                }
            }
        }
        when (format) {
            "zip" -> ZipArchiveOutputStream(out).use { zip ->
                zip.setLevel(6)
                for ((file, name) in files) {
                    if (cancelled()) break
                    val entry = ZipArchiveEntry(file, name)
                    zip.putArchiveEntry(entry)
                    if (file.isFile) {
                        copyInto(file, zip, name)
                        count++
                    }
                    zip.closeArchiveEntry()
                }
                zip.finish()
            }
            "tar", "tgz", "tbz2", "txz" -> {
                val raw = BufferedOutputStream(FileOutputStream(out), 128 * 1024)
                val encoded: OutputStream = when (format) {
                    "tgz" -> GzipCompressorOutputStream(raw)
                    "tbz2" -> BZip2CompressorOutputStream(raw)
                    "txz" -> XZCompressorOutputStream(raw)
                    else -> raw
                }
                TarArchiveOutputStream(encoded).use { tar ->
                    tar.setLongFileMode(TarArchiveOutputStream.LONGFILE_POSIX)
                    tar.setBigNumberMode(TarArchiveOutputStream.BIGNUMBER_POSIX)
                    for ((file, name) in files) {
                        if (cancelled()) break
                        val entry = TarArchiveEntry(file, name)
                        tar.putArchiveEntry(entry)
                        if (file.isFile) {
                            copyInto(file, tar, name)
                            count++
                        }
                        tar.closeArchiveEntry()
                    }
                    tar.finish()
                }
            }
            else -> throw OnyxException("unsupported", "Format kompresi tidak didukung: $format")
        }
        if (cancelled()) out.delete()
        return count
    }

    fun readEntry(file: File, entryName: String, maxBytes: Long): ByteArray {
        val kind = kind(file) ?: throw OnyxException("unsupported", "Format arsip tidak didukung")
        val clean = entryName.trimEnd('/')
        fun slurp(stream: InputStream): ByteArray {
            val out = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(32 * 1024)
            while (true) {
                val read = stream.read(buffer)
                if (read < 0) break
                out.write(buffer, 0, read)
                if (out.size() > maxBytes) throw OnyxException("too_large", "Isi berkas melebihi batas pratinjau")
            }
            return out.toByteArray()
        }
        when (kind) {
            "zip" -> ZipFile.builder().setFile(file).get().use { zip ->
                val entry = zip.getEntry(clean) ?: zip.getEntry("$clean/")
                    ?: throw OnyxException("not_found", "Entri tidak ditemukan di arsip")
                return zip.getInputStream(entry).use { slurp(it) }
            }
            "7z" -> SevenZFile.builder().setFile(file).get().use { z ->
                var e = z.nextEntry
                while (e != null) {
                    if (e.name.trimEnd('/') == clean) {
                        val sevenZ = z
                        val stream = object : InputStream() {
                            override fun read(): Int = sevenZ.read()
                            override fun read(b: ByteArray, off: Int, len: Int): Int = sevenZ.read(b, off, len)
                        }
                        return slurp(stream)
                    }
                    e = z.nextEntry
                }
            }
            "rar" -> Archive(file).use { rar ->
                val header = rar.fileHeaders.firstOrNull { it.fileName == clean }
                    ?: throw OnyxException("not_found", "Entri tidak ditemukan di arsip")
                val buffer = java.io.ByteArrayOutputStream()
                rar.extractFile(header, buffer)
                if (buffer.size() > maxBytes) throw OnyxException("too_large", "Isi berkas melebihi batas pratinjau")
                return buffer.toByteArray()
            }
            "gz", "bz2", "xz" -> throw OnyxException("unsupported", "Arsip satu berkas tidak memiliki entri")
            else -> FileInputStream(file).use { raw ->
                tarStream(kind, raw).use { tar ->
                    var entry = tar.nextEntry
                    while (entry != null) {
                        if (entry.name.trimEnd('/') == clean) return slurp(tar)
                        entry = tar.nextEntry
                    }
                }
            }
        }
        throw OnyxException("not_found", "Entri tidak ditemukan di arsip")
    }
}
