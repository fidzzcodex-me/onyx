package com.onyx.terminal.db

import android.content.ContentValues
import android.database.Cursor

class BookmarkDao(private val database: AppDatabase) {
    fun all(type: String? = null): List<Map<String, Any?>> {
        val db = database.readableDatabase
        val cursor = if (type == null) {
            db.query("bookmarks", null, null, null, null, null, "created_at DESC")
        } else {
            db.query("bookmarks", null, "type = ?", arrayOf(type), null, null, "created_at DESC")
        }
        cursor.use {
            val out = ArrayList<Map<String, Any?>>()
            while (it.moveToNext()) out.add(read(it))
            return out
        }
    }

    fun insert(id: String, type: String, title: String, value: String, extra: String?) {
        val values = ContentValues().apply {
            put("id", id)
            put("type", type)
            put("title", title)
            put("value", value)
            put("extra", extra)
            put("created_at", System.currentTimeMillis())
        }
        database.writableDatabase.insertWithOnConflict(
            "bookmarks", null, values, android.database.sqlite.SQLiteDatabase.CONFLICT_REPLACE
        )
    }

    fun findByValue(type: String, value: String): Map<String, Any?>? {
        database.readableDatabase.query(
            "bookmarks", null, "type = ? AND value = ?", arrayOf(type, value),
            null, null, null, "1"
        ).use {
            return if (it.moveToFirst()) read(it) else null
        }
    }

    fun delete(id: String) {
        database.writableDatabase.delete("bookmarks", "id = ?", arrayOf(id))
    }

    private fun read(cursor: Cursor): Map<String, Any?> = mapOf(
        "id" to cursor.getString(cursor.getColumnIndexOrThrow("id")),
        "type" to cursor.getString(cursor.getColumnIndexOrThrow("type")),
        "title" to cursor.getString(cursor.getColumnIndexOrThrow("title")),
        "value" to cursor.getString(cursor.getColumnIndexOrThrow("value")),
        "extra" to cursor.getString(cursor.getColumnIndexOrThrow("extra")),
        "createdAt" to cursor.getLong(cursor.getColumnIndexOrThrow("created_at"))
    )
}
