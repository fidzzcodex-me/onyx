package com.onyx.terminal.auth

import android.content.Context
import android.util.Patterns
import com.onyx.terminal.db.AppDatabase
import com.onyx.terminal.db.UserDao
import com.onyx.terminal.db.UserRecord
import com.onyx.terminal.security.CredentialStore
import com.onyx.terminal.security.Crypto
import com.onyx.terminal.util.Limits
import com.onyx.terminal.util.OnyxException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class AuthManager(context: Context) {
    private val users = UserDao(AppDatabase.get(context))
    private val sessions = SessionManager(context)
    private val store = CredentialStore.get(context)
    private val failures = ConcurrentHashMap<String, Pair<Int, Long>>()

    @Volatile
    private var verifiedUntil = 0L

    init {
        sessions.coldStart()
    }

    fun markVerified() {
        verifiedUntil = System.currentTimeMillis() + VERIFY_WINDOW_MS
    }

    fun register(name: String, email: String, password: String): User {
        val cleanName = name.trim()
        val cleanEmail = email.trim()
        if (cleanName.length < 2) throw OnyxException("bad_name", "Nama minimal 2 karakter")
        if (!Patterns.EMAIL_ADDRESS.matcher(cleanEmail).matches()) {
            throw OnyxException("bad_email", "Format email tidak valid")
        }
        checkPassword(password)
        if (users.findByEmail(cleanEmail) != null) {
            throw OnyxException("email_taken", "Email sudah terdaftar. Masuk atau gunakan email lain.")
        }
        val salt = Crypto.randomBytes(16)
        val hash = Crypto.argon2id(password.toCharArray(), salt)
        val record = UserRecord(UUID.randomUUID().toString(), cleanName, cleanEmail, salt, hash, System.currentTimeMillis())
        users.insert(record)
        sessions.create(record.id, true)
        return User(record.id, record.name, record.email, false)
    }

    fun login(email: String, password: String, remember: Boolean): User {
        val key = email.trim().lowercase()
        throttleCheck(key)
        val record = users.findByEmail(email)
        if (record == null) {
            fail(key)
            throw OnyxException("bad_credentials", "Email atau password salah")
        }
        val candidate = Crypto.argon2id(password.toCharArray(), record.salt)
        if (!Crypto.constantTimeEquals(candidate, record.hash)) {
            fail(key)
            throw OnyxException("bad_credentials", "Email atau password salah")
        }
        failures.remove(key)
        sessions.create(record.id, remember)
        return User(record.id, record.name, record.email, false)
    }

    fun loginGuest(): User {
        sessions.startGuest()
        return User.GUEST
    }

    fun logout() {
        sessions.clear()
    }

    fun current(): User? = sessions.current()

    fun updateProfile(name: String, email: String): User {
        val user = requireUser()
        if (!Patterns.EMAIL_ADDRESS.matcher(email.trim()).matches()) {
            throw OnyxException("bad_email", "Format email tidak valid")
        }
        val existing = users.findByEmail(email)
        if (existing != null && existing.id != user.id) {
            throw OnyxException("email_taken", "Email sudah dipakai akun lain")
        }
        users.updateProfile(user.id, name.trim(), email.trim())
        return User(user.id, name.trim(), email.trim(), false)
    }

    fun changePassword(oldPassword: String, newPassword: String) {
        val user = requireUser()
        val record = users.findById(user.id) ?: throw OnyxException("no_user", "Akun tidak ditemukan")
        val candidate = Crypto.argon2id(oldPassword.toCharArray(), record.salt)
        if (!Crypto.constantTimeEquals(candidate, record.hash)) {
            throw OnyxException("bad_credentials", "Password lama salah")
        }
        checkPassword(newPassword)
        val salt = Crypto.randomBytes(16)
        users.updateCredentials(record.id, salt, Crypto.argon2id(newPassword.toCharArray(), salt))
    }

    fun resetPassword(email: String, newPassword: String) {
        if (System.currentTimeMillis() > verifiedUntil) {
            throw OnyxException("verification_required", "Verifikasi PIN atau biometrik terlebih dahulu")
        }
        val record = users.findByEmail(email)
            ?: throw OnyxException("no_user", "Email tidak terdaftar di perangkat ini")
        checkPassword(newPassword)
        val salt = Crypto.randomBytes(16)
        users.updateCredentials(record.id, salt, Crypto.argon2id(newPassword.toCharArray(), salt))
        sessions.revokeAllFor(record.id)
        verifiedUntil = 0L
    }

    fun deleteAccount() {
        val user = requireUser()
        sessions.revokeAllFor(user.id)
        users.delete(user.id)
    }

    fun hasAccounts(): Boolean = users.count() > 0

    fun wipeSecrets() {
        store.clearAll()
    }

    private fun requireUser(): User {
        val user = sessions.current() ?: throw OnyxException("not_signed_in", "Belum masuk")
        if (user.isGuest) throw OnyxException("guest", "Fitur ini membutuhkan akun")
        return user
    }

    private fun checkPassword(password: String) {
        if (password.length < Limits.PASSWORD_MIN) {
            throw OnyxException("weak_password", "Password minimal ${Limits.PASSWORD_MIN} karakter")
        }
    }

    private fun throttleCheck(key: String) {
        val state = failures[key] ?: return
        val now = System.currentTimeMillis()
        if (state.first >= MAX_FAILURES && state.second > now) {
            val seconds = (state.second - now) / 1000 + 1
            throw OnyxException("throttled", "Terlalu banyak percobaan. Coba lagi dalam $seconds detik.")
        }
    }

    private fun fail(key: String) {
        val now = System.currentTimeMillis()
        val old = failures[key]
        val count = (if (old != null && old.second + RESET_MS > now) old.first else 0) + 1
        failures[key] = Pair(count, now + LOCK_MS)
    }

    companion object {
        private const val MAX_FAILURES = 5
        private const val LOCK_MS = 60_000L
        private const val RESET_MS = 300_000L
        private const val VERIFY_WINDOW_MS = 120_000L
    }
}
