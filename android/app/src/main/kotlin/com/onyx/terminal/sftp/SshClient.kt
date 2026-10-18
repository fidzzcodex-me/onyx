package com.onyx.terminal.sftp

import android.util.Base64
import com.onyx.terminal.db.ConnectionDao
import com.onyx.terminal.db.ConnectionProfile
import com.onyx.terminal.security.CredentialStore
import com.onyx.terminal.security.Crypto
import com.onyx.terminal.security.KeyManager
import com.onyx.terminal.util.Logger
import com.onyx.terminal.util.OnyxException
import net.schmizz.sshj.AndroidConfig
import net.schmizz.sshj.SSHClient
import net.schmizz.sshj.common.Buffer
import net.schmizz.sshj.transport.verification.HostKeyVerifier
import net.schmizz.sshj.userauth.UserAuthException
import net.schmizz.sshj.userauth.method.AuthKeyboardInteractive
import net.schmizz.sshj.userauth.method.PasswordResponseProvider
import net.schmizz.sshj.userauth.password.PasswordUtils
import java.io.Closeable
import java.io.IOException
import java.net.ConnectException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.Socket
import java.net.SocketAddress
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.security.PublicKey
import javax.net.SocketFactory

class OpenedSsh(val client: SSHClient, private val jump: OpenedSsh?) : Closeable {
    override fun close() {
        try {
            client.disconnect()
        } catch (_: Exception) {
        }
        jump?.close()
    }
}

class HttpConnectSocket(private val proxyHost: String, private val proxyPort: Int) : Socket() {
    override fun connect(endpoint: SocketAddress, timeout: Int) {
        val target = endpoint as InetSocketAddress
        super.connect(InetSocketAddress(proxyHost, proxyPort), timeout)
        val host = target.hostString
        val request = "CONNECT $host:${target.port} HTTP/1.1\r\nHost: $host:${target.port}\r\n\r\n"
        val out = getOutputStream()
        out.write(request.toByteArray(Charsets.ISO_8859_1))
        out.flush()
        val input = getInputStream()
        val header = StringBuilder()
        while (!header.endsWith("\r\n\r\n")) {
            val b = input.read()
            if (b < 0) throw IOException("Proxy menutup koneksi sebelum respons CONNECT")
            header.append(b.toChar())
            if (header.length > 8192) throw IOException("Respons proxy terlalu panjang")
        }
        val status = header.lineSequence().firstOrNull().orEmpty()
        if (!status.contains(" 200")) throw IOException("Proxy menolak CONNECT: $status")
    }
}

class ProxySocketFactory(
    private val type: String,
    private val proxyHost: String,
    private val proxyPort: Int
) : SocketFactory() {
    override fun createSocket(): Socket =
        if (type == "socks") {
            Socket(Proxy(Proxy.Type.SOCKS, InetSocketAddress.createUnresolved(proxyHost, proxyPort)))
        } else {
            HttpConnectSocket(proxyHost, proxyPort)
        }

    override fun createSocket(host: String, port: Int): Socket {
        val socket = createSocket()
        socket.connect(InetSocketAddress.createUnresolved(host, port))
        return socket
    }

    override fun createSocket(host: String, port: Int, localHost: InetAddress?, localPort: Int): Socket =
        createSocket(host, port)

    override fun createSocket(host: InetAddress, port: Int): Socket {
        val socket = createSocket()
        socket.connect(InetSocketAddress(host, port))
        return socket
    }

    override fun createSocket(address: InetAddress, port: Int, localAddress: InetAddress?, localPort: Int): Socket =
        createSocket(address, port)
}

class HostKeyStore(private val dao: ConnectionDao) : HostKeyVerifier {
    @Volatile
    var mismatch: Boolean = false
        private set

    override fun verify(hostname: String, port: Int, key: PublicKey): Boolean {
        val id = "$hostname:$port"
        val blob = Buffer.PlainBuffer().putPublicKey(key).compactData
        val fingerprint = "SHA256:" + Base64.encodeToString(
            Crypto.sha256(blob),
            Base64.NO_WRAP or Base64.NO_PADDING
        )
        val known = dao.knownHost(id)
        if (known == null) {
            dao.saveKnownHost(id, fingerprint)
            Logger.i("ssh", "Kunci host baru dipercaya untuk $id")
            return true
        }
        if (known == fingerprint) return true
        mismatch = true
        return false
    }

    override fun findExistingAlgorithms(hostname: String, port: Int): List<String> = emptyList()
}

class SshClientFactory(
    private val dao: ConnectionDao,
    private val store: CredentialStore,
    private val keys: KeyManager
) {
    fun open(profile: ConnectionProfile, depth: Int = 0): OpenedSsh {
        if (depth > 3) throw OnyxException("jump_loop", "Rantai ProxyJump terlalu dalam")
        val client = SSHClient(AndroidConfig())
        val verifier = HostKeyStore(dao)
        client.addHostKeyVerifier(verifier)
        val timeoutMs = profile.timeoutSec.coerceAtLeast(3) * 1000
        client.connectTimeout = timeoutMs
        client.timeout = timeoutMs
        var jump: OpenedSsh? = null
        try {
            val jumpId = profile.jumpId
            if (!jumpId.isNullOrEmpty()) {
                val jumpProfile = dao.find(jumpId)
                    ?: throw OnyxException("jump_missing", "Profil jump host tidak ditemukan")
                jump = open(jumpProfile, depth + 1)
                client.connectVia(jump.client.newDirectConnection(profile.host, profile.port))
            } else {
                if (profile.proxyType != "none" && !profile.proxyHost.isNullOrBlank()) {
                    client.socketFactory = ProxySocketFactory(profile.proxyType, profile.proxyHost, profile.proxyPort)
                }
                client.connect(profile.host, profile.port)
            }
            authenticate(client, profile)
            if (profile.keepAlive > 0) client.connection.keepAlive.keepAliveInterval = profile.keepAlive
            return OpenedSsh(client, jump)
        } catch (error: Exception) {
            try {
                client.disconnect()
            } catch (_: Exception) {
            }
            jump?.close()
            throw translate(error, verifier, profile)
        }
    }

    private fun authenticate(client: SSHClient, profile: ConnectionProfile) {
        val password = store.get("conn:${profile.id}:pw")
        when (profile.authType) {
            "key" -> {
                val keyId = profile.keyId ?: throw OnyxException("key_missing", "Profil belum memilih kunci SSH")
                client.authPublickey(profile.username, keys.provider(client, keyId))
            }
            "keyboard" -> {
                val secret = password ?: throw OnyxException("secret_missing", "Password belum disimpan")
                client.auth(
                    profile.username,
                    AuthKeyboardInteractive(PasswordResponseProvider(PasswordUtils.createOneOff(secret.toCharArray())))
                )
            }
            else -> {
                val secret = password ?: throw OnyxException("secret_missing", "Password belum disimpan")
                try {
                    client.authPassword(profile.username, secret)
                } catch (error: UserAuthException) {
                    client.auth(
                        profile.username,
                        AuthKeyboardInteractive(PasswordResponseProvider(PasswordUtils.createOneOff(secret.toCharArray())))
                    )
                }
            }
        }
    }

    private fun translate(error: Exception, verifier: HostKeyStore, profile: ConnectionProfile): OnyxException {
        if (error is OnyxException) return error
        if (verifier.mismatch) {
            return OnyxException(
                "host_key_changed",
                "Kunci host ${profile.host}:${profile.port} berubah. Hapus kunci lama dari daftar host tepercaya bila perubahan ini sah.",
                error
            )
        }
        return when (error) {
            is UserAuthException -> OnyxException("auth_failed", "Autentikasi ditolak. Periksa username, password, atau kunci.", error)
            is UnknownHostException -> OnyxException("host_unknown", "Host ${profile.host} tidak ditemukan. Periksa nama host.", error)
            is ConnectException -> OnyxException("connect_failed", "Tidak dapat terhubung ke ${profile.host}:${profile.port}.", error)
            is SocketTimeoutException -> OnyxException("timeout", "Koneksi ke ${profile.host} melewati batas waktu.", error)
            else -> OnyxException("connect_failed", error.message ?: error.javaClass.simpleName, error)
        }
    }
}
