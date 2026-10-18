package com.onyx.terminal.db

import android.content.ContentValues

data class SessionRecord(
    val tokenHash: String,
    val userId: String,
    val persist: Boolean,
    val createdAt: Long,
    val lastSeen: Long,
    val expiresAt: Long
)

class SessionDao(private val database: AppDatabase) {
    fun insert(record: SessionRecord) {
        val values = ContentValues().apply {
            put("token_hash", record.tokenHash)
            put("user_id", record.userId)
            put("persist", if (record.persist) 1 else 0)
            put("created_at", record.createdAt)
            put("last_seen", record.lastSeen)
            put("expires_at", record.expiresAt)
        }
        database.writableDatabase.insertOrThrow("sessions", null, values)
    }

    fun find(tokenHash: String): SessionRecord? {
        database.readableDatabase.query(
            "sessions", null, "token_hash = ?", arrayOf(tokenHash), null, null, null, "1"
        ).use {
            if (!it.moveToFirst()) return null
            return SessionRecord(
                tokenHash = it.getString(it.getColumnIndexOrThrow("token_hash")),
                userId = it.getString(it.getColumnIndexOrThrow("user_id")),
                persist = it.getInt(it.getColumnIndexOrThrow("persist")) == 1,
                createdAt = it.getLong(it.getColumnIndexOrThrow("created_at")),
                lastSeen = it.getLong(it.getColumnIndexOrThrow("last_seen")),
                expiresAt = it.getLong(it.getColumnIndexOrThrow("expires_at"))
            )
        }
    }

    fun touch(tokenHash: String, now: Long) {
        val values = ContentValues().apply { put("last_seen", now) }
        database.writableDatabase.update("sessions", values, "token_hash = ?", arrayOf(tokenHash))
    }

    fun delete(tokenHash: String) {
        database.writableDatabase.delete("sessions", "token_hash = ?", arrayOf(tokenHash))
    }

    fun deleteForUser(userId: String) {
        database.writableDatabase.delete("sessions", "user_id = ?", arrayOf(userId))
    }

    fun deleteEphemeral() {
        database.writableDatabase.delete("sessions", "persist = 0", null)
    }

    fun deleteExpired(now: Long) {
        database.writableDatabase.delete("sessions", "expires_at < ?", arrayOf(now.toString()))
    }
}
