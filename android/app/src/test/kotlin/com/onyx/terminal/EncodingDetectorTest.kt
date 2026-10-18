package com.onyx.terminal

import com.onyx.terminal.editor.EncodingDetector
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EncodingDetectorTest {
    @Test
    fun detectsUtf8Bom() {
        val sample = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte(), 'a'.code.toByte())
        val detected = EncodingDetector.detect(sample)
        assertEquals("UTF-8", detected.name)
        assertTrue(detected.hasBom)
        assertEquals(3, detected.bomLength)
    }

    @Test
    fun detectsPlainUtf8() {
        val detected = EncodingDetector.detect("halo dunia".toByteArray(Charsets.UTF_8))
        assertEquals("UTF-8", detected.name)
        assertFalse(detected.hasBom)
    }

    @Test
    fun fallsBackForInvalidUtf8() {
        val detected = EncodingDetector.detect(byteArrayOf(0x68, 0xE9, 0x6C, 0x6C, 0x6F))
        assertEquals("windows-1252", detected.name)
    }

    @Test
    fun nulByteMeansBinary() {
        assertTrue(EncodingDetector.looksBinary(byteArrayOf(0x7F, 0x45, 0x4C, 0x46, 0x00, 0x01)))
        assertFalse(EncodingDetector.looksBinary("teks biasa\nbaris dua\n".toByteArray()))
        assertFalse(EncodingDetector.looksBinary(ByteArray(0)))
    }

    @Test
    fun detectsLineEndings() {
        assertEquals("lf", EncodingDetector.lineEnding("a\nb\nc"))
        assertEquals("crlf", EncodingDetector.lineEnding("a\r\nb\r\nc"))
        assertEquals("cr", EncodingDetector.lineEnding("a\rb\rc"))
    }
}
