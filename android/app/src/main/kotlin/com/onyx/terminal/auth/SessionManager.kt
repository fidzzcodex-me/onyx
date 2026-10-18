package com.onyx.terminal.auth

import android.content.Context
import com.onyx.terminal.db.AppDatabase
import com.onyx.terminal.db.SessionDao
import com.onyx.terminal.db.SessionRecord
import com.onyx.terminal.db.UserDao
import com.onyx.terminal.security.Crypto
import com.onyx.terminal.security.CredentialStore
import com.onyx.terminal.util.Limits
import com.onyx.terminal.util.toHex

data class User(val id: String, val name: String, val email: String, val isGuest: Boolean) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "name" to name,
        "email" to email,
        "isGuest" to isGuest
    )

    companion object {
        val GUEST = User("guest", "Guest", "", true)
    }
}

class SessionManager(context: Context) {
    private val store = CredentialStore.get(context)
    private val sessions = SessionDao(AppDatabase.get(context))
    private val users = UserDao(AppDatabase.get(context))

    fun create(userId: String, persist: Boolean): String {
        val token = Crypto.randomBytes(32).toHex()
        val now = System.currentTimeMillis()
        val ttl = if (persist) Limits.MAX_SESSION_AGE_PERSIST_MS else Limits.MAX_SESSION_AGE_EPHEMERAL_MS
        sessions.insert(
            SessionRecord(hashOf(token), userId, persist, now, now, now + ttl)
        )
        store.put(KEY_TOKEN, token)
        store.remove(KEY_GUEST)
        return token
    }

    fun startGuest() {
        clear()
        store.put(KEY_GUEST, "1")
    }

    fun current(): User? {
        if (store.contains(KEY_GUEST)) return User.GUEST
        val token = store.get(KEY_TOKEN) ?: return null
        val record = sessions.find(hashOf(token)) ?: return null
        val now = System.currentTimeMillis()
        if (record.expiresAt < now) {
            clear()
            return null
        }
        val user = users.findById(record.userId) ?: return null
        sessions.touch(record.tokenHash, now)
        return User(user.id, user.name, user.email, false)
    }

    fun clear() {
        val token = store.get(KEY_TOKEN)
        if (token != null) sessions.delete(hashOf(token))
        store.remove(KEY_TOKEN)
        store.remove(KEY_GUEST)
    }

    fun revokeAllFor(userId: String) {
        sessions.deleteForUser(userId)
        store.remove(KEY_TOKEN)
    }

    fun coldStart() {
        if (coldStarted) return
        coldStarted = true
        sessions.deleteExpired(System.currentTimeMillis())
        sessions.deleteEphemeral()
        store.remove(KEY_GUEST)
    }

    private fun hashOf(token: String): String =
        Crypto.sha256(token.toByteArray(Charsets.UTF_8)).toHex()

    companion object {
        private const val KEY_TOKEN = "session.token"
        private const val KEY_GUEST = "session.guest"

        @Volatile
        private var coldStarted = false
    }
}
