package com.onyx.terminal.db

import android.content.ContentValues
import android.database.Cursor

data class UserRecord(
    val id: String,
    val name: String,
    val email: String,
    val salt: ByteArray,
    val hash: ByteArray,
    val createdAt: Long
)

class UserDao(private val database: AppDatabase) {
    fun insert(user: UserRecord) {
        val values = ContentValues().apply {
            put("id", user.id)
            put("name", user.name)
            put("email", user.email)
            put("salt", user.salt)
            put("hash", user.hash)
            put("created_at", user.createdAt)
        }
        database.writableDatabase.insertOrThrow("users", null, values)
    }

    fun findByEmail(email: String): UserRecord? =
        query("email = ? COLLATE NOCASE", arrayOf(email.trim()))

    fun findById(id: String): UserRecord? = query("id = ?", arrayOf(id))

    fun updateProfile(id: String, name: String, email: String) {
        val values = ContentValues().apply {
            put("name", name)
            put("email", email)
        }
        database.writableDatabase.update("users", values, "id = ?", arrayOf(id))
    }

    fun updateCredentials(id: String, salt: ByteArray, hash: ByteArray) {
        val values = ContentValues().apply {
            put("salt", salt)
            put("hash", hash)
        }
        database.writableDatabase.update("users", values, "id = ?", arrayOf(id))
    }

    fun delete(id: String) {
        database.writableDatabase.delete("users", "id = ?", arrayOf(id))
    }

    fun count(): Int {
        database.readableDatabase.rawQuery("SELECT COUNT(*) FROM users", null).use {
            return if (it.moveToFirst()) it.getInt(0) else 0
        }
    }

    private fun query(where: String, args: Array<String>): UserRecord? {
        database.readableDatabase.query("users", null, where, args, null, null, null, "1").use {
            return if (it.moveToFirst()) read(it) else null
        }
    }

    private fun read(cursor: Cursor): UserRecord = UserRecord(
        id = cursor.getString(cursor.getColumnIndexOrThrow("id")),
        name = cursor.getString(cursor.getColumnIndexOrThrow("name")),
        email = cursor.getString(cursor.getColumnIndexOrThrow("email")),
        salt = cursor.getBlob(cursor.getColumnIndexOrThrow("salt")),
        hash = cursor.getBlob(cursor.getColumnIndexOrThrow("hash")),
        createdAt = cursor.getLong(cursor.getColumnIndexOrThrow("created_at"))
    )
}
