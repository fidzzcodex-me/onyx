package com.onyx.terminal.db

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class AppDatabase private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, NAME, null, VERSION) {

    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        db.setForeignKeyConstraintsEnabled(true)
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE users (" +
                "id TEXT PRIMARY KEY, name TEXT NOT NULL, " +
                "email TEXT NOT NULL UNIQUE COLLATE NOCASE, " +
                "salt BLOB NOT NULL, hash BLOB NOT NULL, created_at INTEGER NOT NULL)"
        )
        db.execSQL(
            "CREATE TABLE sessions (" +
                "token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL, " +
                "persist INTEGER NOT NULL, created_at INTEGER NOT NULL, " +
                "last_seen INTEGER NOT NULL, expires_at INTEGER NOT NULL, " +
                "FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE)"
        )
        db.execSQL(
            "CREATE TABLE bookmarks (" +
                "id TEXT PRIMARY KEY, type TEXT NOT NULL, title TEXT NOT NULL, " +
                "value TEXT NOT NULL, extra TEXT, created_at INTEGER NOT NULL)"
        )
        db.execSQL("CREATE INDEX idx_bookmarks_type ON bookmarks(type)")
        db.execSQL(
            "CREATE TABLE connections (" +
                "id TEXT PRIMARY KEY, name TEXT NOT NULL, protocol TEXT NOT NULL, " +
                "host TEXT NOT NULL, port INTEGER NOT NULL, username TEXT NOT NULL, " +
                "auth_type TEXT NOT NULL, key_id TEXT, proxy_type TEXT NOT NULL DEFAULT 'none', " +
                "proxy_host TEXT, proxy_port INTEGER NOT NULL DEFAULT 0, jump_id TEXT, " +
                "keep_alive INTEGER NOT NULL DEFAULT 15, timeout_sec INTEGER NOT NULL DEFAULT 20, " +
                "initial_path TEXT, options TEXT, last_used INTEGER NOT NULL DEFAULT 0, " +
                "created_at INTEGER NOT NULL)"
        )
        db.execSQL(
            "CREATE TABLE ssh_keys (" +
                "id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, " +
                "public_key TEXT NOT NULL, fingerprint TEXT NOT NULL, created_at INTEGER NOT NULL)"
        )
        db.execSQL(
            "CREATE TABLE known_hosts (" +
                "host_key TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, created_at INTEGER NOT NULL)"
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
    }

    companion object {
        private const val NAME = "onyx.db"
        private const val VERSION = 1

        @Volatile
        private var instance: AppDatabase? = null

        fun get(context: Context): AppDatabase =
            instance ?: synchronized(this) {
                instance ?: AppDatabase(context).also { instance = it }
            }
    }
}
