package com.onyx.terminal.viewer

import com.onyx.terminal.editor.EncodingDetector
import com.onyx.terminal.util.Limits
import com.onyx.terminal.util.OnyxException
import org.json.JSONArray
import org.json.JSONObject
import java.io.FileInputStream

class DocumentViewer {
    private fun text(path: String): String {
        val file = requireFile(path)
        if (file.length() > Limits.MAX_PREVIEW_BYTES * 8) {
            throw OnyxException("too_large", "Berkas terlalu besar untuk pratinjau dokumen")
        }
        val bytes = FileInputStream(file).use { it.readBytes() }
        val detected = EncodingDetector.detect(bytes.copyOf(minOf(bytes.size, 8192)))
        return String(bytes, detected.bomLength, bytes.size - detected.bomLength, detected.charset)
    }

    fun json(path: String): Map<String, Any?> {
        val raw = text(path).trim()
        return try {
            val pretty = if (raw.startsWith("[")) JSONArray(raw).toString(2) else JSONObject(raw).toString(2)
            mapOf("ok" to true, "text" to pretty)
        } catch (error: Exception) {
            mapOf("ok" to false, "text" to raw, "error" to (error.message ?: "JSON tidak valid"))
        }
    }

    fun csv(path: String, maxRows: Int): Map<String, Any?> {
        val raw = text(path)
        val first = raw.lineSequence().firstOrNull { it.isNotBlank() } ?: ""
        val delimiter = listOf(',', ';', '\t', '|').maxByOrNull { d -> first.count { it == d } } ?: ','
        val rows = ArrayList<List<String>>()
        val field = StringBuilder()
        var row = ArrayList<String>()
        var quoted = false
        var i = 0
        while (i < raw.length && rows.size < maxRows) {
            val c = raw[i]
            if (quoted) {
                if (c == '"') {
                    if (i + 1 < raw.length && raw[i + 1] == '"') {
                        field.append('"')
                        i++
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(c)
                }
            } else when (c) {
                '"' -> quoted = true
                delimiter -> {
                    row.add(field.toString())
                    field.setLength(0)
                }
                '\r' -> {}
                '\n' -> {
                    row.add(field.toString())
                    field.setLength(0)
                    if (row.any { it.isNotEmpty() }) rows.add(row)
                    row = ArrayList()
                }
                else -> field.append(c)
            }
            i++
        }
        if (rows.size < maxRows && (field.isNotEmpty() || row.isNotEmpty())) {
            row.add(field.toString())
            rows.add(row)
        }
        return mapOf(
            "delimiter" to delimiter.toString(),
            "rows" to rows,
            "columns" to (rows.maxOfOrNull { it.size } ?: 0),
            "truncated" to (i < raw.length)
        )
    }

    fun plain(path: String): String = text(path)
}
