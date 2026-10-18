package com.onyx.terminal.sftp

import android.content.Context
import com.onyx.terminal.db.AppDatabase
import com.onyx.terminal.db.ConnectionDao
import com.onyx.terminal.db.ConnectionProfile
import com.onyx.terminal.security.CredentialStore
import com.onyx.terminal.security.KeyManager
import com.onyx.terminal.util.Logger
import com.onyx.terminal.util.OnyxException
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class RemoteSession(val id: String, val profile: ConnectionProfile, @Volatile var fs: RemoteFs)

class ConnectionManager(private val context: Context) {
    val dao = ConnectionDao(AppDatabase.get(context))
    val store: CredentialStore = CredentialStore.get(context)
    val keys = KeyManager(dao, store)
    private val factory = SshClientFactory(dao, store, keys)
    private val sessions = ConcurrentHashMap<String, RemoteSession>()

    fun profile(id: String): ConnectionProfile =
        dao.find(id) ?: throw OnyxException("no_profile", "Profil koneksi tidak ditemukan")

    fun listProfiles(): List<Map<String, Any?>> = dao.all().map { it.toMap(hasSecret(it)) }

    private fun hasSecret(profile: ConnectionProfile): Boolean =
        store.contains("conn:${profile.id}:pw") || !profile.keyId.isNullOrEmpty()

    fun saveProfile(input: Map<String, Any?>): Map<String, Any?> {
        val protocol = (input["protocol"] as? String ?: "sftp").lowercase()
        if (protocol !in setOf("sftp", "scp", "ftp", "ftps", "webdav")) {
            throw OnyxException("bad_protocol", "Protokol tidak didukung: $protocol")
        }
        val host = (input["host"] as? String)?.trim().orEmpty()
        if (host.isEmpty()) throw OnyxException("bad_host", "Host wajib diisi")
        val defaultPort = when (protocol) {
            "ftp" -> 21
            "ftps" -> 21
            "webdav" -> 443
            else -> 22
        }
        val port = (input["port"] as? Number)?.toInt() ?: defaultPort
        if (port !in 1..65535) throw OnyxException("bad_port", "Port harus antara 1 dan 65535")
        val username = (input["username"] as? String)?.trim().orEmpty()
        if (username.isEmpty()) throw OnyxException("bad_user", "Username wajib diisi")
        val id = (input["id"] as? String)?.takeIf { it.isNotEmpty() } ?: UUID.randomUUID().toString()
        val existing = dao.find(id)
        val options = try {
            JSONObject((input["options"] as? String)?.takeIf { it.isNotBlank() } ?: "{}")
        } catch (_: Exception) {
            JSONObject()
        }
        val authType = (input["authType"] as? String) ?: "password"
        val profile = ConnectionProfile(
            id = id,
            name = (input["name"] as? String)?.trim()?.ifEmpty { null } ?: "$username@$host",
            protocol = protocol,
            host = host,
            port = port,
            username = username,
            authType = authType,
            keyId = (input["keyId"] as? String)?.takeIf { it.isNotEmpty() },
            proxyType = (input["proxyType"] as? String) ?: "none",
            proxyHost = (input["proxyHost"] as? String)?.takeIf { it.isNotBlank() },
            proxyPort = (input["proxyPort"] as? Number)?.toInt() ?: 0,
            jumpId = (input["jumpId"] as? String)?.takeIf { it.isNotEmpty() },
            keepAlive = (input["keepAlive"] as? Number)?.toInt() ?: 15,
            timeoutSec = (input["timeoutSec"] as? Number)?.toInt() ?: 20,
            initialPath = (input["initialPath"] as? String)?.takeIf { it.isNotBlank() },
            options = options,
            lastUsed = existing?.lastUsed ?: 0L,
            createdAt = existing?.createdAt ?: System.currentTimeMillis()
        )
        dao.upsert(profile)
        val secret = input["secret"] as? String
        if (secret != null && secret.isNotEmpty()) store.put("conn:$id:pw", secret)
        if (authType == "key") store.remove("conn:$id:pw")
        return profile.toMap(hasSecret(profile))
    }

    fun deleteProfile(id: String) {
        sessions.values.filter { it.profile.id == id }.forEach { disconnect(it.id) }
        dao.delete(id)
        store.remove("conn:$id:pw")
    }

    fun openSsh(profileId: String): OpenedSsh {
        val profile = profile(profileId)
        if (profile.protocol != "sftp" && profile.protocol != "scp") {
            throw OnyxException("not_ssh", "Profil ini bukan koneksi SSH")
        }
        dao.touchUsed(profileId)
        return factory.open(profile)
    }

    fun connect(profileId: String): String {
        val profile = profile(profileId)
        val fs = createFs(profile)
        dao.touchUsed(profileId)
        val id = UUID.randomUUID().toString()
        sessions[id] = RemoteSession(id, profile, fs)
        return id
    }

    fun test(input: Map<String, Any?>): Map<String, Any?> {
        val secret = input["secret"] as? String
        val tempId = "test-" + UUID.randomUUID().toString()
        val existingId = input["id"] as? String
        val started = System.currentTimeMillis()
        val tempProfile = ConnectionProfile(
            id = tempId,
            name = "test",
            protocol = ((input["protocol"] as? String) ?: "sftp").lowercase(),
            host = (input["host"] as? String)?.trim().orEmpty(),
            port = (input["port"] as? Number)?.toInt() ?: 22,
            username = (input["username"] as? String)?.trim().orEmpty(),
            authType = (input["authType"] as? String) ?: "password",
            keyId = (input["keyId"] as? String)?.takeIf { it.isNotEmpty() },
            proxyType = (input["proxyType"] as? String) ?: "none",
            proxyHost = (input["proxyHost"] as? String)?.takeIf { it.isNotBlank() },
            proxyPort = (input["proxyPort"] as? Number)?.toInt() ?: 0,
            jumpId = (input["jumpId"] as? String)?.takeIf { it.isNotEmpty() },
            keepAlive = 0,
            timeoutSec = (input["timeoutSec"] as? Number)?.toInt() ?: 15,
            initialPath = (input["initialPath"] as? String)?.takeIf { it.isNotBlank() },
            options = try {
                JSONObject((input["options"] as? String)?.takeIf { it.isNotBlank() } ?: "{}")
            } catch (_: Exception) {
                JSONObject()
            },
            lastUsed = 0L,
            createdAt = 0L
        )
        if (tempProfile.host.isEmpty() || tempProfile.username.isEmpty()) {
            throw OnyxException("bad_args", "Host dan username wajib diisi")
        }
        val pw = if (!secret.isNullOrEmpty()) secret else existingId?.let { store.get("conn:$it:pw") }
        if (pw != null) store.put("conn:$tempId:pw", pw)
        try {
            val fs = createFs(tempProfile)
            try {
                val home = fs.home()
                val count = try {
                    fs.list(home).size
                } catch (_: Exception) {
                    -1
                }
                return mapOf(
                    "ok" to true,
                    "latencyMs" to (System.currentTimeMillis() - started),
                    "home" to home,
                    "entries" to count
                )
            } finally {
                fs.close()
            }
        } finally {
            store.remove("conn:$tempId:pw")
        }
    }

    fun session(id: String): RemoteSession =
        sessions[id] ?: throw OnyxException("no_session", "Sesi koneksi sudah ditutup")

    fun fs(id: String): RemoteFs {
        val session = session(id)
        if (!session.fs.isAlive()) {
            Logger.i("sftp", "Menyambung ulang ${session.profile.name}")
            try {
                session.fs.close()
            } catch (_: Exception) {
            }
            session.fs = createFs(session.profile)
        }
        return session.fs
    }

    fun disconnect(id: String) {
        val session = sessions.remove(id) ?: return
        try {
            session.fs.close()
        } catch (_: Exception) {
        }
    }

    fun disconnectAll() {
        for (id in sessions.keys.toList()) disconnect(id)
    }

    fun forgetHost(host: String, port: Int) {
        dao.forgetHost("$host:$port")
    }

    private fun createFs(profile: ConnectionProfile): RemoteFs {
        val password = store.get("conn:${profile.id}:pw")
        return when (profile.protocol) {
            "sftp" -> SftpRemoteFs(factory.open(profile), false)
            "scp" -> SftpRemoteFs(factory.open(profile), true)
            "ftp" -> FtpRemoteFs(profile, password ?: throw missingSecret(), false)
            "ftps" -> FtpRemoteFs(profile, password ?: throw missingSecret(), true)
            "webdav" -> WebDavRemoteFs(profile, password ?: throw missingSecret())
            else -> throw OnyxException("bad_protocol", "Protokol tidak didukung: ${profile.protocol}")
        }
    }

    private fun missingSecret() = OnyxException("secret_missing", "Password belum disimpan untuk profil ini")
}
