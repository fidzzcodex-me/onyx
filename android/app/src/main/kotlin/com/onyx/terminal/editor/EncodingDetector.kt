package com.onyx.terminal.editor

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

data class Detected(val charset: Charset, val name: String, val bomLength: Int, val hasBom: Boolean)

object EncodingDetector {
    private val supported = linkedMapOf(
        "UTF-8" to "UTF-8",
        "UTF-16LE" to "UTF-16LE",
        "UTF-16BE" to "UTF-16BE",
        "ISO-8859-1" to "ISO-8859-1",
        "windows-1252" to "windows-1252",
        "windows-1251" to "windows-1251",
        "Shift_JIS" to "Shift_JIS",
        "GBK" to "GBK",
        "EUC-KR" to "EUC-KR",
        "US-ASCII" to "US-ASCII"
    )

    fun available(): List<String> = supported.keys.toList()

    fun charsetOrNull(name: String?): Charset? {
        if (name == null) return null
        return try {
            Charset.forName(supported[name] ?: name)
        } catch (_: Exception) {
            null
        }
    }

    fun detect(sample: ByteArray): Detected {
        if (sample.size >= 3 && sample[0] == 0xEF.toByte() && sample[1] == 0xBB.toByte() && sample[2] == 0xBF.toByte()) {
            return Detected(Charsets.UTF_8, "UTF-8", 3, true)
        }
        if (sample.size >= 2 && sample[0] == 0xFF.toByte() && sample[1] == 0xFE.toByte()) {
            return Detected(Charsets.UTF_16LE, "UTF-16LE", 2, true)
        }
        if (sample.size >= 2 && sample[0] == 0xFE.toByte() && sample[1] == 0xFF.toByte()) {
            return Detected(Charsets.UTF_16BE, "UTF-16BE", 2, true)
        }
        val utf16 = guessUtf16(sample)
        if (utf16 != null) return utf16
        if (isValidUtf8(sample)) {
            return Detected(Charsets.UTF_8, "UTF-8", 0, false)
        }
        return Detected(Charset.forName("windows-1252"), "windows-1252", 0, false)
    }

    private fun guessUtf16(sample: ByteArray): Detected? {
        if (sample.size < 8) return null
        var evenZero = 0
        var oddZero = 0
        val limit = minOf(sample.size, 4096)
        for (i in 0 until limit) {
            if (sample[i] == 0.toByte()) {
                if (i % 2 == 0) evenZero++ else oddZero++
            }
        }
        val pairs = limit / 2
        if (oddZero > pairs * 0.3 && evenZero < pairs * 0.05) return Detected(Charsets.UTF_16LE, "UTF-16LE", 0, false)
        if (evenZero > pairs * 0.3 && oddZero < pairs * 0.05) return Detected(Charsets.UTF_16BE, "UTF-16BE", 0, false)
        return null
    }

    fun isValidUtf8(bytes: ByteArray): Boolean {
        val decoder = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        var end = bytes.size
        if (end == 0) return true
        var back = 0
        while (back < 4 && end > 0 && (bytes[end - 1].toInt() and 0xC0) == 0x80) {
            end--
            back++
        }
        if (end > 0 && (bytes[end - 1].toInt() and 0x80) != 0) end--
        return try {
            decoder.decode(ByteBuffer.wrap(bytes, 0, end))
            true
        } catch (_: CharacterCodingException) {
            false
        }
    }

    fun looksBinary(sample: ByteArray): Boolean {
        if (sample.isEmpty()) return false
        val detected = detect(sample)
        if (detected.name.startsWith("UTF-16")) return false
        var control = 0
        for (b in sample) {
            val v = b.toInt() and 0xff
            if (v == 0) return true
            if (v < 9 || (v in 14..31 && v != 27)) control++
        }
        return control * 100 / sample.size > 8
    }

    fun lineEnding(text: String): String {
        var crlf = 0
        var lf = 0
        var cr = 0
        var i = 0
        val limit = minOf(text.length, 200_000)
        while (i < limit) {
            val c = text[i]
            if (c == '\r') {
                if (i + 1 < text.length && text[i + 1] == '\n') {
                    crlf++
                    i++
                } else {
                    cr++
                }
            } else if (c == '\n') {
                lf++
            }
            i++
        }
        return when {
            crlf > lf && crlf >= cr -> "crlf"
            cr > lf && cr > crlf -> "cr"
            else -> "lf"
        }
    }
}
