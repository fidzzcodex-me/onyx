package com.onyx.terminal.sftp

import com.onyx.terminal.db.ConnectionProfile
import com.onyx.terminal.util.OnyxException
import org.apache.commons.net.ftp.FTP
import org.apache.commons.net.ftp.FTPClient
import org.apache.commons.net.ftp.FTPFile
import org.apache.commons.net.ftp.FTPReply
import org.apache.commons.net.ftp.FTPSClient
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Proxy
import java.time.Duration

class FtpRemoteFs(
    private val profile: ConnectionProfile,
    private val password: String,
    private val tls: Boolean
) : RemoteFs {
    override val protocol: String = if (tls) "ftps" else "ftp"
    private val control: FTPClient = connectNew()

    private fun connectNew(): FTPClient {
        val client: FTPClient = if (tls) FTPSClient(profile.port == 990) else FTPClient()
        val timeoutMs = profile.timeoutSec.coerceAtLeast(3) * 1000
        client.connectTimeout = timeoutMs
        client.defaultTimeout = timeoutMs
        client.controlEncoding = "UTF-8"
        if (profile.proxyType == "socks" && !profile.proxyHost.isNullOrBlank()) {
            client.setProxy(
                Proxy(Proxy.Type.SOCKS, InetSocketAddress.createUnresolved(profile.proxyHost, profile.proxyPort))
            )
        }
        try {
            client.connect(profile.host, profile.port)
            if (!FTPReply.isPositiveCompletion(client.replyCode)) {
                throw OnyxException("ftp_refused", "Server FTP menolak koneksi (${client.replyString.trim()})")
            }
            if (!client.login(profile.username, password)) {
                throw OnyxException("auth_failed", "Login FTP ditolak. Periksa username dan password.")
            }
            if (client is FTPSClient) {
                client.execPBSZ(0)
                client.execPROT("P")
            }
            client.enterLocalPassiveMode()
            client.setFileType(FTP.BINARY_FILE_TYPE)
            client.soTimeout = timeoutMs
            if (profile.keepAlive > 0) {
                client.setControlKeepAliveTimeout(Duration.ofSeconds(profile.keepAlive.toLong()))
            }
            return client
        } catch (error: Exception) {
            try {
                client.disconnect()
            } catch (_: Exception) {
            }
            if (error is OnyxException) throw error
            throw OnyxException("connect_failed", error.message ?: "Koneksi FTP gagal", error)
        }
    }

    @Synchronized
    override fun home(): String = control.printWorkingDirectory() ?: "/"

    @Synchronized
    override fun list(path: String): List<RemoteEntry> {
        var files: Array<FTPFile> = try {
            control.mlistDir(path) ?: emptyArray()
        } catch (_: Exception) {
            emptyArray()
        }
        if (files.isEmpty()) files = control.listFiles(path) ?: emptyArray()
        val out = ArrayList<RemoteEntry>()
        for (file in files) {
            val name = file.name ?: continue
            if (name == "." || name == "..") continue
            out.add(toEntry(file, RemotePath.join(path, name)))
        }
        return out
    }

    @Synchronized
    override fun stat(path: String): RemoteEntry? {
        return try {
            val file = control.mlistFile(path) ?: return null
            toEntry(file, path)
        } catch (_: Exception) {
            null
        }
    }

    @Synchronized
    override fun mkdir(path: String) {
        var current = if (path.startsWith("/")) "" else "."
        for (part in path.split('/').filter { it.isNotEmpty() }) {
            current = "$current/$part"
            val target = current.removePrefix("./")
            control.makeDirectory(target)
        }
    }

    @Synchronized
    override fun delete(path: String, recursive: Boolean) {
        val entry = stat(path)
        if (entry != null && !entry.isDir) {
            control.deleteFile(path)
            return
        }
        if (recursive) {
            for (child in list(path)) delete(child.path, true)
        }
        if (!control.removeDirectory(path)) control.deleteFile(path)
    }

    @Synchronized
    override fun rename(from: String, to: String) {
        if (!control.rename(from, to)) {
            throw OnyxException("rename_failed", "Server menolak penggantian nama: ${control.replyString.trim()}")
        }
    }

    @Synchronized
    override fun chmod(path: String, mode: Int) {
        val octal = Integer.toOctalString(mode and 0xfff)
        if (!FTPReply.isPositiveCompletion(control.sendSiteCommand("CHMOD $octal $path"))) {
            throw OnyxException("unsupported", "Server FTP tidak mendukung CHMOD")
        }
    }

    @Synchronized
    override fun readBytes(path: String, maxBytes: Long): ByteArray {
        val out = ByteArrayOutputStream()
        if (!control.retrieveFile(path, out)) {
            throw OnyxException("read_failed", "Gagal membaca berkas: ${control.replyString.trim()}")
        }
        if (out.size() > maxBytes) throw OnyxException("too_large", "Berkas melebihi batas baca")
        return out.toByteArray()
    }

    @Synchronized
    override fun writeBytes(path: String, data: ByteArray) {
        if (!control.storeFile(path, ByteArrayInputStream(data))) {
            throw OnyxException("write_failed", "Gagal menulis berkas: ${control.replyString.trim()}")
        }
    }

    override fun download(remote: String, local: File, offset: Long, progress: (Long) -> Unit) {
        val client = connectNew()
        try {
            val resumeAt = if (offset > 0 && local.exists() && local.length() == offset) offset else 0L
            local.parentFile?.mkdirs()
            client.restartOffset = resumeAt
            val input = client.retrieveFileStream(remote)
                ?: throw OnyxException("read_failed", "Server menolak unduhan: ${client.replyString.trim()}")
            var finished = false
            try {
                FileOutputStream(local, resumeAt > 0).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var done = resumeAt
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        done += count
                        progress(done)
                    }
                }
                finished = true
            } finally {
                try {
                    input.close()
                } catch (_: IOException) {
                }
                if (finished) {
                    client.completePendingCommand()
                } else {
                    try {
                        client.abort()
                    } catch (_: Exception) {
                    }
                }
            }
        } finally {
            try {
                client.disconnect()
            } catch (_: Exception) {
            }
        }
    }

    override fun upload(local: File, remote: String, offset: Long, progress: (Long) -> Unit) {
        val client = connectNew()
        try {
            val output = (if (offset > 0) client.appendFileStream(remote) else client.storeFileStream(remote))
                ?: throw OnyxException("write_failed", "Server menolak unggahan: ${client.replyString.trim()}")
            var finished = false
            try {
                FileInputStream(local).use { input ->
                    if (offset > 0) input.skip(offset)
                    val buffer = ByteArray(64 * 1024)
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
                finished = true
            } finally {
                try {
                    output.close()
                } catch (_: IOException) {
                }
                if (finished) client.completePendingCommand()
            }
        } finally {
            try {
                client.disconnect()
            } catch (_: Exception) {
            }
        }
    }

    @Synchronized
    override fun isAlive(): Boolean = try {
        control.isConnected && control.sendNoOp()
    } catch (_: Exception) {
        false
    }

    override fun close() {
        try {
            control.logout()
        } catch (_: Exception) {
        }
        try {
            control.disconnect()
        } catch (_: Exception) {
        }
    }

    private fun toEntry(file: FTPFile, path: String): RemoteEntry {
        val perms = StringBuilder(10)
        perms.append(if (file.isSymbolicLink) 'l' else if (file.isDirectory) 'd' else '-')
        val groups = intArrayOf(FTPFile.USER_ACCESS, FTPFile.GROUP_ACCESS, FTPFile.WORLD_ACCESS)
        for (group in groups) {
            perms.append(if (file.hasPermission(group, FTPFile.READ_PERMISSION)) 'r' else '-')
            perms.append(if (file.hasPermission(group, FTPFile.WRITE_PERMISSION)) 'w' else '-')
            perms.append(if (file.hasPermission(group, FTPFile.EXECUTE_PERMISSION)) 'x' else '-')
        }
        return RemoteEntry(
            name = file.name,
            path = path,
            isDir = file.isDirectory,
            size = if (file.isDirectory) 0L else file.size,
            modified = file.timestamp?.timeInMillis ?: 0L,
            mode = perms.toString(),
            isLink = file.isSymbolicLink
        )
    }
}
