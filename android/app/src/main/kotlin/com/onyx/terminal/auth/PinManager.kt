package com.onyx.terminal.auth

import android.content.Context
import com.onyx.terminal.security.CredentialStore
import com.onyx.terminal.security.Crypto
import com.onyx.terminal.util.Limits
import com.onyx.terminal.util.OnyxException

class PinManager(context: Context) {
    private val store = CredentialStore.get(context)

    fun hasPin(): Boolean = store.contains(KEY_HASH)

    fun set(pin: String) {
        validate(pin)
        val salt = Crypto.randomBytes(16)
        val hash = Crypto.argon2id(pin.toCharArray(), salt)
        store.put(KEY_SALT, Crypto.b64(salt))
        store.put(KEY_HASH, Crypto.b64(hash))
        resetFailures()
    }

    fun clear() {
        store.remove(KEY_SALT)
        store.remove(KEY_HASH)
        resetFailures()
    }

    fun verify(pin: String): Map<String, Any?> {
        val now = System.currentTimeMillis()
        val lockUntil = store.get(KEY_LOCK_UNTIL)?.toLongOrNull() ?: 0L
        if (lockUntil > now) {
            return mapOf("ok" to false, "lockedMs" to (lockUntil - now), "attemptsLeft" to 0)
        }
        val saltText = store.get(KEY_SALT)
        val hashText = store.get(KEY_HASH)
        if (saltText == null || hashText == null) {
            throw OnyxException("no_pin", "PIN belum diatur")
        }
        val candidate = Crypto.argon2id(pin.toCharArray(), Crypto.unb64(saltText))
        if (Crypto.constantTimeEquals(candidate, Crypto.unb64(hashText))) {
            resetFailures()
            return mapOf("ok" to true, "lockedMs" to 0L, "attemptsLeft" to MAX_FAILURES)
        }
        val failures = (store.get(KEY_FAILURES)?.toIntOrNull() ?: 0) + 1
        if (failures >= MAX_FAILURES) {
            val rounds = (failures / MAX_FAILURES).coerceAtMost(6)
            val wait = BASE_LOCK_MS * (1L shl (rounds - 1))
            store.put(KEY_LOCK_UNTIL, (now + wait).toString())
            store.put(KEY_FAILURES, failures.toString())
            return mapOf("ok" to false, "lockedMs" to wait, "attemptsLeft" to 0)
        }
        store.put(KEY_FAILURES, failures.toString())
        return mapOf(
            "ok" to false,
            "lockedMs" to 0L,
            "attemptsLeft" to (MAX_FAILURES - failures)
        )
    }

    private fun resetFailures() {
        store.remove(KEY_FAILURES)
        store.remove(KEY_LOCK_UNTIL)
    }

    private fun validate(pin: String) {
        if (pin.length < Limits.PIN_MIN || pin.length > Limits.PIN_MAX || !pin.all { it in '0'..'9' }) {
            throw OnyxException("bad_pin", "PIN harus ${Limits.PIN_MIN} sampai ${Limits.PIN_MAX} digit angka")
        }
    }

    companion object {
        private const val KEY_SALT = "pin.salt"
        private const val KEY_HASH = "pin.hash"
        private const val KEY_FAILURES = "pin.failures"
        private const val KEY_LOCK_UNTIL = "pin.lock_until"
        private const val MAX_FAILURES = 5
        private const val BASE_LOCK_MS = 30_000L
    }
}
