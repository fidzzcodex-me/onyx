package com.onyx.terminal.db

import android.content.ContentValues
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject

data class ConnectionProfile(
    val id: String,
    val name: String,
    val protocol: String,
    val host: String,
    val port: Int,
    val username: String,
    val authType: String,
    val keyId: String?,
    val proxyType: String,
    val proxyHost: String?,
    val proxyPort: Int,
    val jumpId: String?,
    val keepAlive: Int,
    val timeoutSec: Int,
    val initialPath: String?,
    val options: JSONObject,
    val lastUsed: Long,
    val createdAt: Long
) {
    fun toMap(hasSecret: Boolean): Map<String, Any?> = mapOf(
        "id" to id,
        "name" to name,
        "protocol" to protocol,
        "host" to host,
        "port" to port,
        "username" to username,
        "authType" to authType,
        "keyId" to keyId,
        "proxyType" to proxyType,
        "proxyHost" to proxyHost,
        "proxyPort" to proxyPort,
        "jumpId" to jumpId,
        "keepAlive" to keepAlive,
        "timeoutSec" to timeoutSec,
        "initialPath" to initialPath,
        "options" to options.toString(),
        "lastUsed" to lastUsed,
        "createdAt" to createdAt,
        "hasSecret" to hasSecret
    )
}

data class SshKeyRecord(
    val id: String,
    val name: String,
    val type: String,
    val publicKey: String,
    val fingerprint: String,
    val createdAt: Long
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "name" to name,
        "type" to type,
        "publicKey" to publicKey,
        "fingerprint" to fingerprint,
        "createdAt" to createdAt
    )
}

class ConnectionDao(private val database: AppDatabase) {
    fun all(): List<ConnectionProfile> {
        database.readableDatabase.query(
            "connections", null, null, null, null, null, "last_used DESC, name COLLATE NOCASE ASC"
        ).use {
            val out = ArrayList<ConnectionProfile>()
            while (it.moveToNext()) out.add(read(it))
            return out
        }
    }

    fun find(id: String): ConnectionProfile? {
        database.readableDatabase.query(
            "connections", null, "id = ?", arrayOf(id), null, null, null, "1"
        ).use {
            return if (it.moveToFirst()) read(it) else null
        }
    }

    fun upsert(profile: ConnectionProfile) {
        val values = ContentValues().apply {
            put("id", profile.id)
            put("name", profile.name)
            put("protocol", profile.protocol)
            put("host", profile.host)
            put("port", profile.port)
            put("username", profile.username)
            put("auth_type", profile.authType)
            put("key_id", profile.keyId)
            put("proxy_type", profile.proxyType)
            put("proxy_host", profile.proxyHost)
            put("proxy_port", profile.proxyPort)
            put("jump_id", profile.jumpId)
            put("keep_alive", profile.keepAlive)
            put("timeout_sec", profile.timeoutSec)
            put("initial_path", profile.initialPath)
            put("options", profile.options.toString())
            put("last_used", profile.lastUsed)
            put("created_at", profile.createdAt)
        }
        database.writableDatabase.insertWithOnConflict(
            "connections", null, values, SQLiteDatabase.CONFLICT_REPLACE
        )
    }

    fun touchUsed(id: String) {
        val values = ContentValues().apply { put("last_used", System.currentTimeMillis()) }
        database.writableDatabase.update("connections", values, "id = ?", arrayOf(id))
    }

    fun delete(id: String) {
        database.writableDatabase.delete("connections", "id = ?", arrayOf(id))
    }

    fun keys(): List<SshKeyRecord> {
        database.readableDatabase.query(
            "ssh_keys", null, null, null, null, null, "created_at DESC"
        ).use {
            val out = ArrayList<SshKeyRecord>()
            while (it.moveToNext()) out.add(readKey(it))
            return out
        }
    }

    fun findKey(id: String): SshKeyRecord? {
        database.readableDatabase.query(
            "ssh_keys", null, "id = ?", arrayOf(id), null, null, null, "1"
        ).use {
            return if (it.moveToFirst()) readKey(it) else null
        }
    }

    fun insertKey(record: SshKeyRecord) {
        val values = ContentValues().apply {
            put("id", record.id)
            put("name", record.name)
            put("type", record.type)
            put("public_key", record.publicKey)
            put("fingerprint", record.fingerprint)
            put("created_at", record.createdAt)
        }
        database.writableDatabase.insertOrThrow("ssh_keys", null, values)
    }

    fun deleteKey(id: String) {
        database.writableDatabase.delete("ssh_keys", "id = ?", arrayOf(id))
    }

    fun knownHost(hostKey: String): String? {
        database.readableDatabase.query(
            "known_hosts", arrayOf("fingerprint"), "host_key = ?", arrayOf(hostKey),
            null, null, null, "1"
        ).use {
            return if (it.moveToFirst()) it.getString(0) else null
        }
    }

    fun saveKnownHost(hostKey: String, fingerprint: String) {
        val values = ContentValues().apply {
            put("host_key", hostKey)
            put("fingerprint", fingerprint)
            put("created_at", System.currentTimeMillis())
        }
        database.writableDatabase.insertWithOnConflict(
            "known_hosts", null, values, SQLiteDatabase.CONFLICT_REPLACE
        )
    }

    fun forgetHost(hostKey: String) {
        database.writableDatabase.delete("known_hosts", "host_key = ?", arrayOf(hostKey))
    }

    private fun read(c: Cursor): ConnectionProfile {
        val rawOptions = c.getString(c.getColumnIndexOrThrow("options"))
        val options = try {
            if (rawOptions.isNullOrBlank()) JSONObject() else JSONObject(rawOptions)
        } catch (_: Exception) {
            JSONObject()
        }
        return ConnectionProfile(
            id = c.getString(c.getColumnIndexOrThrow("id")),
            name = c.getString(c.getColumnIndexOrThrow("name")),
            protocol = c.getString(c.getColumnIndexOrThrow("protocol")),
            host = c.getString(c.getColumnIndexOrThrow("host")),
            port = c.getInt(c.getColumnIndexOrThrow("port")),
            username = c.getString(c.getColumnIndexOrThrow("username")),
            authType = c.getString(c.getColumnIndexOrThrow("auth_type")),
            keyId = c.getString(c.getColumnIndexOrThrow("key_id")),
            proxyType = c.getString(c.getColumnIndexOrThrow("proxy_type")),
            proxyHost = c.getString(c.getColumnIndexOrThrow("proxy_host")),
            proxyPort = c.getInt(c.getColumnIndexOrThrow("proxy_port")),
            jumpId = c.getString(c.getColumnIndexOrThrow("jump_id")),
            keepAlive = c.getInt(c.getColumnIndexOrThrow("keep_alive")),
            timeoutSec = c.getInt(c.getColumnIndexOrThrow("timeout_sec")),
            initialPath = c.getString(c.getColumnIndexOrThrow("initial_path")),
            options = options,
            lastUsed = c.getLong(c.getColumnIndexOrThrow("last_used")),
            createdAt = c.getLong(c.getColumnIndexOrThrow("created_at"))
        )
    }

    private fun readKey(c: Cursor): SshKeyRecord = SshKeyRecord(
        id = c.getString(c.getColumnIndexOrThrow("id")),
        name = c.getString(c.getColumnIndexOrThrow("name")),
        type = c.getString(c.getColumnIndexOrThrow("type")),
        publicKey = c.getString(c.getColumnIndexOrThrow("public_key")),
        fingerprint = c.getString(c.getColumnIndexOrThrow("fingerprint")),
        createdAt = c.getLong(c.getColumnIndexOrThrow("created_at"))
    )
}
