package com.onyx.terminal.security

import android.content.Context
import android.content.SharedPreferences
import com.onyx.terminal.util.Logger
import com.onyx.terminal.util.Prefs

class CredentialStore private constructor(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(Prefs.SECURE, Context.MODE_PRIVATE)

    fun put(key: String, value: String) {
        prefs.edit().putString(key, Crypto.encryptString(value, key)).apply()
    }

    fun get(key: String): String? {
        val raw = prefs.getString(key, null) ?: return null
        return try {
            Crypto.decryptString(raw, key)
        } catch (error: Exception) {
            Logger.w("credential", "Gagal mendekripsi entri", error)
            null
        }
    }

    fun contains(key: String): Boolean = prefs.contains(key)

    fun remove(key: String) {
        prefs.edit().remove(key).apply()
    }

    fun removePrefix(prefix: String) {
        val editor = prefs.edit()
        for (key in prefs.all.keys) {
            if (key.startsWith(prefix)) editor.remove(key)
        }
        editor.apply()
    }

    fun clearAll() {
        prefs.edit().clear().apply()
    }

    companion object {
        @Volatile
        private var instance: CredentialStore? = null

        fun get(context: Context): CredentialStore =
            instance ?: synchronized(this) {
                instance ?: CredentialStore(context).also { instance = it }
            }
    }
}
