package com.onyx.terminal.sftp

import com.onyx.terminal.util.OnyxException
import com.onyx.terminal.util.modeToString
import net.schmizz.sshj.common.StreamCopier
import net.schmizz.sshj.sftp.FileAttributes
import net.schmizz.sshj.sftp.OpenMode
import net.schmizz.sshj.sftp.RemoteResourceInfo
import net.schmizz.sshj.sftp.SFTPClient
import net.schmizz.sshj.xfer.FileSystemFile
import net.schmizz.sshj.xfer.TransferListener
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

data class RemoteEntry(
    val name: String,
    val path: String,
    val isDir: Boolean,
    val size: Long,
    val modified: Long,
    val mode: String,
    val isLink: Boolean
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "name" to name,
        "path" to path,
        "isDir" to isDir,
        "size" to size,
        "modified" to modified,
        "mode" to mode,
        "isLink" to isLink
    )
}

interface RemoteFs : Closeable {
    val protocol: String
    fun home(): String
    fun list(path: String): List<RemoteEntry>
    fun stat(path: String): RemoteEntry?
    fun mkdir(path: String)
    fun delete(path: String, recursive: Boolean)
    fun rename(from: String, to: String)
    fun chmod(path: String, mode: Int)
    fun readBytes(path: String, maxBytes: Long): ByteArray
    fun writeBytes(path: String, data: ByteArray)
    fun download(remote: String, local: File, offset: Long, progress: (Long) -> Unit)
    fun upload(local: File, remote: String, offset: Long, progress: (Long) -> Unit)
    fun isAlive(): Boolean
}

object RemotePath {
    fun join(base: String, name: String): String =
        if (base.endsWith("/")) base + name else "$base/$name"

    fun parent(path: String): String {
        val trimmed = path.trimEnd('/')
        val index = trimmed.lastIndexOf('/')
        return when {
            index < 0 -> "/"
            index == 0 -> "/"
            else -> trimmed.substring(0, index)
        }
    }

    fun name(path: String): String = path.trimEnd('/').substringAfterLast('/')
}

class SftpRemoteFs(private val opened: OpenedSsh, private val useScp: Boolean) : RemoteFs {
    private val sftp: SFTPClient = opened.client.newSFTPClient()
    override val protocol: String = if (useScp) "scp" else "sftp"

    override fun home(): String = sftp.canonicalize(".")

    override fun list(path: String): List<RemoteEntry> {
        val out = ArrayList<RemoteEntry>()
        for (info in sftp.ls(path)) {
            if (info.name == "." || info.name == "..") continue
            out.add(toEntry(info))
        }
        return out
    }

    override fun stat(path: String): RemoteEntry? {
        return try {
            val attrs = sftp.stat(path)
            fromAttributes(RemotePath.name(path), path, attrs, false)
        } catch (_: Exception) {
            null
        }
    }

    override fun mkdir(path: String) {
        sftp.mkdirs(path)
    }

    override fun delete(path: String, recursive: Boolean) {
        val entry = stat(path) ?: return
        if (!entry.isDir) {
            sftp.rm(path)
            return
        }
        if (recursive) {
            for (child in list(path)) delete(child.path, true)
        }
        sftp.rmdir(path)
    }

    override fun rename(from: String, to: String) {
        sftp.rename(from, to)
    }

    override fun chmod(path: String, mode: Int) {
        sftp.chmod(path, mode)
    }

    override fun readBytes(path: String, maxBytes: Long): ByteArray {
        val file = sftp.open(path, setOf(OpenMode.READ))
        file.use { remote ->
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(32 * 1024)
            var offset = 0L
            while (offset < maxBytes) {
                val want = minOf(buffer.size.toLong(), maxBytes - offset).toInt()
                val count = remote.read(offset, buffer, 0, want)
                if (count < 0) break
                out.write(buffer, 0, count)
                offset += count
            }
            return out.toByteArray()
        }
    }

    override fun writeBytes(path: String, data: ByteArray) {
        val file = sftp.open(path, setOf(OpenMode.WRITE, OpenMode.CREAT, OpenMode.TRUNC))
        file.use { remote ->
            var offset = 0
            while (offset < data.size) {
                val length = minOf(32 * 1024, data.size - offset)
                remote.write(offset.toLong(), data, offset, length)
                offset += length
            }
        }
    }

    override fun download(remote: String, local: File, offset: Long, progress: (Long) -> Unit) {
        if (useScp) {
            val transfer = opened.client.newSCPFileTransfer()
            transfer.transferListener = scpListener(progress)
            transfer.download(remote, FileSystemFile(local))
            return
        }
        val resumeAt = if (offset > 0 && local.exists() && local.length() == offset) offset else 0L
        local.parentFile?.mkdirs()
        val file = sftp.open(remote, setOf(OpenMode.READ))
        file.use { handle ->
            val input = handle.ReadAheadRemoteFileInputStream(16, resumeAt)
            FileOutputStream(local, resumeAt > 0).use { output ->
                val buffer = ByteArray(128 * 1024)
                var done = resumeAt
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    output.write(buffer, 0, count)
                    done += count
                    progress(done)
                }
            }
        }
    }

    override fun upload(local: File, remote: String, offset: Long, progress: (Long) -> Unit) {
        if (useScp) {
            val transfer = opened.client.newSCPFileTransfer()
            transfer.transferListener = scpListener(progress)
            transfer.upload(FileSystemFile(local), remote)
            return
        }
        val modes = if (offset > 0) {
            setOf(OpenMode.WRITE, OpenMode.CREAT)
        } else {
            setOf(OpenMode.WRITE, OpenMode.CREAT, OpenMode.TRUNC)
        }
        val file = sftp.open(remote, modes)
        file.use { handle ->
            val output = handle.RemoteFileOutputStream(offset, 16)
            FileInputStream(local).use { input ->
                if (offset > 0) input.skip(offset)
                val buffer = ByteArray(128 * 1024)
                var done = offset
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    output.write(buffer, 0, count)
                    done += count
                    progress(done)
                }
                output.flush()
            }
            output.close()
        }
    }

    override fun isAlive(): Boolean = opened.client.isConnected && opened.client.isAuthenticated

    override fun close() {
        try {
            sftp.close()
        } catch (_: Exception) {
        }
        opened.close()
    }

    private fun scpListener(progress: (Long) -> Unit): TransferListener = object : TransferListener {
        override fun directory(name: String): TransferListener = this

        override fun file(name: String, size: Long): StreamCopier.Listener =
            StreamCopier.Listener { transferred -> progress(transferred) }
    }

    private fun toEntry(info: RemoteResourceInfo): RemoteEntry =
        fromAttributes(info.name, info.path, info.attributes, info.isDirectory)

    private fun fromAttributes(name: String, path: String, attrs: FileAttributes, dirHint: Boolean): RemoteEntry {
        val isLink = attrs.type.name.startsWith("SYM")
        var isDir = dirHint || attrs.type.name == "DIRECTORY"
        if (isLink) {
            isDir = try {
                sftp.stat(path).type.name == "DIRECTORY"
            } catch (_: Exception) {
                false
            }
        }
        return RemoteEntry(
            name = name,
            path = path,
            isDir = isDir,
            size = if (isDir) 0L else attrs.size,
            modified = attrs.mtime * 1000L,
            mode = modeToString(attrs.mode.mask, isDir, isLink),
            isLink = isLink
        )
    }

    init {
        if (opened.client.isConnected.not()) throw OnyxException("not_connected", "Koneksi SSH terputus")
    }
}
