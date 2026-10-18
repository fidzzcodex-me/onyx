package com.onyx.terminal

import com.onyx.terminal.filesystem.ArchiveEngine
import com.onyx.terminal.util.OnyxException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class ArchiveEngineTest {
    @get:Rule
    val temp = TemporaryFolder()

    @Test
    fun zipRoundTripKeepsContent() {
        val source = temp.newFolder("sumber")
        File(source, "a.txt").writeText("isi a")
        File(source, "sub").mkdirs()
        File(source, "sub/b.txt").writeText("isi b")
        val archive = File(temp.root, "hasil.zip")
        val engine = ArchiveEngine()
        engine.create(listOf(source), archive, "zip", { _, _ -> }) { false }
        assertTrue(archive.exists())
        val dest = temp.newFolder("tujuan")
        engine.extract(archive, dest, null, { _, _ -> }) { false }
        assertEquals("isi a", File(dest, "sumber/a.txt").readText())
        assertEquals("isi b", File(dest, "sumber/sub/b.txt").readText())
    }

    @Test
    fun zipSlipIsRejected() {
        val archive = File(temp.root, "jahat.zip")
        ZipOutputStream(archive.outputStream()).use { zip ->
            zip.putNextEntry(ZipEntry("../keluar.txt"))
            zip.write("x".toByteArray())
            zip.closeEntry()
        }
        val dest = temp.newFolder("aman")
        try {
            ArchiveEngine().extract(archive, dest, null, { _, _ -> }) { false }
            fail("Ekstraksi jalur berbahaya seharusnya ditolak")
        } catch (error: OnyxException) {
            assertEquals("zip_slip", error.code)
        }
        assertTrue(!File(temp.root, "keluar.txt").exists())
    }
}
