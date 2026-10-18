package com.onyx.terminal.security

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.bouncycastle.crypto.generators.Argon2BytesGenerator
import org.bouncycastle.crypto.params.Argon2Parameters
import org.bouncycastle.jce.provider.BouncyCastleProvider
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.Security
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

object Crypto {
    private const val KEY_ALIAS = "onyx_master_v1"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_TAG_BITS = 128
    private const val GCM_IV_BYTES = 12
    private const val ARGON_MEMORY_KB = 19456
    private const val ARGON_ITERATIONS = 2

    private val random = SecureRandom()

    @Volatile
    private var providerReady = false

    fun init() {
        if (providerReady) return
        synchronized(this) {
            if (providerReady) return
            Security.removeProvider(BouncyCastleProvider.PROVIDER_NAME)
            Security.insertProviderAt(BouncyCastleProvider(), 1)
            providerReady = true
        }
    }

    fun randomBytes(size: Int): ByteArray {
        val out = ByteArray(size)
        random.nextBytes(out)
        return out
    }

    fun sha256(data: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(data)

    fun constantTimeEquals(a: ByteArray, b: ByteArray): Boolean = MessageDigest.isEqual(a, b)

    fun argon2id(secret: CharArray, salt: ByteArray, length: Int = 32): ByteArray {
        val params = Argon2Parameters.Builder(Argon2Parameters.ARGON2_id)
            .withVersion(Argon2Parameters.ARGON2_VERSION_13)
            .withSalt(salt)
            .withParallelism(1)
            .withMemoryAsKB(ARGON_MEMORY_KB)
            .withIterations(ARGON_ITERATIONS)
            .build()
        val generator = Argon2BytesGenerator()
        generator.init(params)
        val out = ByteArray(length)
        generator.generateBytes(secret, out)
        return out
    }

    private fun masterKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null)
        val existing = keyStore.getKey(KEY_ALIAS, null)
        if (existing is SecretKey) return existing
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    fun encrypt(plain: ByteArray, aad: ByteArray? = null): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, masterKey())
        if (aad != null) cipher.updateAAD(aad)
        val cipherText = cipher.doFinal(plain)
        return cipher.iv + cipherText
    }

    fun decrypt(blob: ByteArray, aad: ByteArray? = null): ByteArray {
        require(blob.size > GCM_IV_BYTES) { "Data terenkripsi tidak valid" }
        val iv = blob.copyOfRange(0, GCM_IV_BYTES)
        val cipherText = blob.copyOfRange(GCM_IV_BYTES, blob.size)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, masterKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
        if (aad != null) cipher.updateAAD(aad)
        return cipher.doFinal(cipherText)
    }

    fun encryptString(value: String, aad: String? = null): String {
        val blob = encrypt(value.toByteArray(Charsets.UTF_8), aad?.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(blob, Base64.NO_WRAP)
    }

    fun decryptString(value: String, aad: String? = null): String {
        val blob = Base64.decode(value, Base64.NO_WRAP)
        return String(decrypt(blob, aad?.toByteArray(Charsets.UTF_8)), Charsets.UTF_8)
    }

    fun b64(data: ByteArray): String = Base64.encodeToString(data, Base64.NO_WRAP)

    fun unb64(data: String): ByteArray = Base64.decode(data, Base64.NO_WRAP)
}
