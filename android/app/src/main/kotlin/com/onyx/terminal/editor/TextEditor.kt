package com.onyx.terminal.editor

import com.onyx.terminal.util.Limits
import com.onyx.terminal.util.OnyxException
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

class TextEditor {
    fun languageOf(file: File): String {
        val name = file.name.lowercase()
        val byName = mapOf(
            "dockerfile" to "dockerfile",
            "makefile" to "makefile",
            "cmakelists.txt" to "cmake",
            ".bashrc" to "bash",
            ".profile" to "bash",
            ".zshrc" to "bash",
            ".gitignore" to "plaintext",
            ".env" to "ini"
        )
        byName[name]?.let { return it }
        return when (file.extension.lowercase()) {
            "kt", "kts" -> "kotlin"
            "java" -> "java"
            "dart" -> "dart"
            "js", "mjs", "cjs", "jsx" -> "javascript"
            "ts", "tsx" -> "typescript"
            "json" -> "json"
            "yaml", "yml" -> "yaml"
            "xml", "svg", "plist" -> "xml"
            "html", "htm", "vue" -> "xml"
            "css" -> "css"
            "scss", "sass" -> "scss"
            "md", "markdown" -> "markdown"
            "py" -> "python"
            "rb" -> "ruby"
            "go" -> "go"
            "rs" -> "rust"
            "c", "h" -> "c"
            "cpp", "cc", "cxx", "hpp" -> "cpp"
            "cs" -> "cs"
            "swift" -> "swift"
            "php" -> "php"
            "lua" -> "lua"
            "sh", "bash", "zsh" -> "bash"
            "sql" -> "sql"
            "toml", "ini", "conf", "cfg", "properties" -> "ini"
            "gradle" -> "gradle"
            "diff", "patch" -> "diff"
            else -> "plaintext"
        }
    }

    fun read(path: String, encodingOverride: String?): Map<String, Any?> {
        val file = File(path)
        if (!file.exists()) throw OnyxException("not_found", "Berkas tidak ditemukan")
        if (!file.isFile) throw OnyxException("not_file", "Hanya berkas yang dapat dibuka di editor")
        if (!file.canRead()) throw OnyxException("denied", "Tidak ada izin membaca berkas ini")
        if (file.length() > Limits.MAX_EDITABLE_BYTES) {
            throw OnyxException(
                "too_large",
                "Berkas ${file.length() / 1024 / 1024} MB melebihi batas editor ${Limits.MAX_EDITABLE_BYTES / 1024 / 1024} MB"
            )
        }
        val bytes = FileInputStream(file).use { it.readBytes() }
        val sample = if (bytes.size > 8192) bytes.copyOf(8192) else bytes
        if (encodingOverride == null && EncodingDetector.looksBinary(sample)) {
            throw OnyxException("binary", "Berkas ini tampak biner. Buka dengan penampil hex.")
        }
        val override = EncodingDetector.charsetOrNull(encodingOverride)
        val detected = EncodingDetector.detect(sample)
        val charset = override ?: detected.charset
        val skip = if (override == null || override == detected.charset) detected.bomLength else 0
        val decoder = charset.newDecoder()
            .onMalformedInput(CodingErrorAction.REPLACE)
            .onUnmappableCharacter(CodingErrorAction.REPLACE)
        val text = decoder.decode(ByteBuffer.wrap(bytes, skip, bytes.size - skip)).toString()
        val ending = EncodingDetector.lineEnding(text)
        val normalized = when (ending) {
            "crlf" -> text.replace("\r\n", "\n")
            "cr" -> text.replace('\r', '\n')
            else -> text
        }
        return mapOf(
            "path" to file.absolutePath,
            "text" to normalized,
            "encoding" to (encodingOverride ?: detected.name),
            "bom" to (detected.hasBom && skip > 0),
            "lineEnding" to ending,
            "size" to file.length(),
            "modified" to file.lastModified(),
            "readonly" to !file.canWrite(),
            "language" to languageOf(file),
            "encodings" to EncodingDetector.available()
        )
    }

    fun write(
        path: String,
        text: String,
        encoding: String,
        lineEnding: String,
        bom: Boolean,
        backup: Boolean,
        expectedModified: Long?
    ): Map<String, Any?> {
        val file = File(path)
        if (file.exists() && !file.canWrite()) throw OnyxException("denied", "Berkas ini hanya-baca")
        if (expectedModified != null && expectedModified > 0 && file.exists() &&
            Math.abs(file.lastModified() - expectedModified) > 1000
        ) {
            throw OnyxException("conflict", "Berkas berubah di luar editor. Muat ulang atau timpa.")
        }
        val charset = EncodingDetector.charsetOrNull(encoding) ?: Charsets.UTF_8
        val converted = when (lineEnding) {
            "crlf" -> text.replace("\r\n", "\n").replace("\n", "\r\n")
            "cr" -> text.replace("\r\n", "\n").replace("\n", "\r")
            else -> text.replace("\r\n", "\n")
        }
        val encoder = charset.newEncoder()
            .onMalformedInput(CodingErrorAction.REPLACE)
            .onUnmappableCharacter(CodingErrorAction.REPLACE)
        val body = encoder.encode(java.nio.CharBuffer.wrap(converted))
        val payload = ByteArray(body.remaining())
        body.get(payload)
        val prefix = if (bom) when (charset.name()) {
            "UTF-8" -> byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())
            "UTF-16LE" -> byteArrayOf(0xFF.toByte(), 0xFE.toByte())
            "UTF-16BE" -> byteArrayOf(0xFE.toByte(), 0xFF.toByte())
            else -> ByteArray(0)
        } else ByteArray(0)
        file.parentFile?.mkdirs()
        if (backup && file.exists()) {
            file.copyTo(File(file.parentFile, file.name + "~"), overwrite = true)
        }
        val temp = File(file.parentFile, "." + file.name + ".onyx-tmp")
        try {
            FileOutputStream(temp).use { output ->
                output.write(prefix)
                output.write(payload)
                output.fd.sync()
            }
            if (file.exists()) {
                try {
                    val mode = android.system.Os.stat(file.absolutePath).st_mode and 0xfff
                    android.system.Os.chmod(temp.absolutePath, mode)
                } catch (_: Exception) {
                }
            }
            if (!temp.renameTo(file)) {
                FileOutputStream(file).use { it.write(prefix); it.write(payload) }
                temp.delete()
            }
        } catch (error: Exception) {
            temp.delete()
            if (error is OnyxException) throw error
            throw OnyxException("write_failed", "Gagal menyimpan: ${error.message}", error)
        }
        return mapOf("size" to file.length(), "modified" to file.lastModified())
    }
}
