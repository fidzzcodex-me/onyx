package com.onyx.terminal.viewer

import com.onyx.terminal.util.OnyxException
import java.io.RandomAccessFile

class HexViewer {
    fun read(path: String, offset: Long, length: Int): Map<String, Any?> {
        val file = requireFile(path)
        val size = file.length()
        if (offset < 0 || offset > size) throw OnyxException("bad_offset", "Offset di luar ukuran berkas")
        val count = length.coerceIn(1, 64 * 1024).toLong().coerceAtMost(size - offset).toInt()
        val buffer = ByteArray(count)
        RandomAccessFile(file, "r").use {
            it.seek(offset)
            it.readFully(buffer)
        }
        return mapOf("offset" to offset, "bytes" to buffer, "size" to size)
    }

    fun find(path: String, needle: ByteArray, from: Long): Long {
        if (needle.isEmpty()) return -1L
        val file = requireFile(path)
        val size = file.length()
        val chunk = 256 * 1024
        RandomAccessFile(file, "r").use { raf ->
            var position = from.coerceAtLeast(0L)
            val buffer = ByteArray(chunk + needle.size)
            while (position < size) {
                raf.seek(position)
                val read = raf.read(buffer, 0, buffer.size)
                if (read <= 0) break
                val limit = read - needle.size
                var i = 0
                while (i <= limit) {
                    var match = true
                    for (j in needle.indices) {
                        if (buffer[i + j] != needle[j]) {
                            match = false
                            break
                        }
                    }
                    if (match) return position + i
                    i++
                }
                if (read < buffer.size) break
                position += chunk
            }
        }
        return -1L
    }
}
