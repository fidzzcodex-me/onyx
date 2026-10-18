package com.onyx.terminal.security

import android.util.Base64
import com.onyx.terminal.db.ConnectionDao
import com.onyx.terminal.db.SshKeyRecord
import com.onyx.terminal.util.OnyxException
import com.onyx.terminal.util.toSshMpint
import net.i2p.crypto.eddsa.EdDSAPrivateKey
import net.i2p.crypto.eddsa.EdDSAPublicKey
import net.schmizz.sshj.SSHClient
import net.schmizz.sshj.common.Buffer
import net.schmizz.sshj.common.KeyType
import net.schmizz.sshj.userauth.keyprovider.KeyProvider
import net.schmizz.sshj.userauth.password.PasswordUtils
import java.io.ByteArrayOutputStream
import java.math.BigInteger
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PublicKey
import java.security.SecureRandom
import java.security.interfaces.ECPrivateKey
import java.security.interfaces.ECPublicKey
import java.security.interfaces.RSAPrivateCrtKey
import java.security.interfaces.RSAPublicKey
import java.security.spec.ECGenParameterSpec
import java.util.UUID

private class Wire {
    private val out = ByteArrayOutputStream()

    fun raw(bytes: ByteArray): Wire {
        out.write(bytes)
        return this
    }

    fun int(value: Int): Wire {
        out.write(byteArrayOf((value ushr 24).toByte(), (value ushr 16).toByte(), (value ushr 8).toByte(), value.toByte()))
        return this
    }

    fun string(bytes: ByteArray): Wire {
        int(bytes.size)
        out.write(bytes)
        return this
    }

    fun string(text: String): Wire = string(text.toByteArray(Charsets.UTF_8))

    fun mpint(value: BigInteger): Wire = string(value.toSshMpint())

    fun bytes(): ByteArray = out.toByteArray()
}

class KeyManager(private val dao: ConnectionDao, private val store: CredentialStore) {
    private val random = SecureRandom()

    fun list(): List<SshKeyRecord> = dao.keys()

    fun generate(type: String, name: String): SshKeyRecord {
        val label = name.trim().ifEmpty { "onyx-key" }
        val pair: KeyPair
        val publicBlob: ByteArray
        val privateSection: ByteArray
        val keyType: String
        when (type) {
            "rsa" -> {
                val generator = KeyPairGenerator.getInstance("RSA")
                generator.initialize(3072, random)
                pair = generator.generateKeyPair()
                val pub = pair.public as RSAPublicKey
                val priv = pair.private as RSAPrivateCrtKey
                keyType = "ssh-rsa"
                publicBlob = Wire().string(keyType).mpint(pub.publicExponent).mpint(pub.modulus).bytes()
                privateSection = Wire()
                    .string(keyType)
                    .mpint(priv.modulus)
                    .mpint(priv.publicExponent)
                    .mpint(priv.privateExponent)
                    .mpint(priv.crtCoefficient)
                    .mpint(priv.primeP)
                    .mpint(priv.primeQ)
                    .bytes()
            }
            "ecdsa" -> {
                val generator = KeyPairGenerator.getInstance("EC")
                generator.initialize(ECGenParameterSpec("secp384r1"), random)
                pair = generator.generateKeyPair()
                val pub = pair.public as ECPublicKey
                val priv = pair.private as ECPrivateKey
                keyType = "ecdsa-sha2-nistp384"
                val point = encodePoint(pub, 48)
                publicBlob = Wire().string(keyType).string("nistp384").string(point).bytes()
                privateSection = Wire()
                    .string(keyType)
                    .string("nistp384")
                    .string(point)
                    .mpint(priv.s)
                    .bytes()
            }
            "ed25519" -> {
                val generator = KeyPairGenerator.getInstance("EdDSA", net.i2p.crypto.eddsa.EdDSASecurityProvider())
                pair = generator.generateKeyPair()
                val pub = pair.public as EdDSAPublicKey
                val priv = pair.private as EdDSAPrivateKey
                keyType = "ssh-ed25519"
                val pk = pub.abyte
                val seed = priv.seed
                publicBlob = Wire().string(keyType).string(pk).bytes()
                privateSection = Wire()
                    .string(keyType)
                    .string(pk)
                    .string(seed + pk)
                    .bytes()
            }
            else -> throw OnyxException("bad_key_type", "Jenis kunci tidak didukung: $type")
        }
        val pem = openSshPrivatePem(publicBlob, privateSection, label)
        val publicLine = "$keyType ${Base64.encodeToString(publicBlob, Base64.NO_WRAP)} $label"
        return persist(label, keyType, publicLine, publicBlob, pem)
    }

    fun import(name: String, pem: String, passphrase: String?): SshKeyRecord {
        val client = SSHClient()
        val finder = passphrase?.takeIf { it.isNotEmpty() }?.let { PasswordUtils.createOneOff(it.toCharArray()) }
        val provider: KeyProvider = try {
            client.loadKeys(pem, null, finder)
        } catch (error: Exception) {
            throw OnyxException("bad_key", "Kunci tidak dapat dibaca. Periksa format dan passphrase.", error)
        }
        val pub: PublicKey = provider.getPublic()
        val keyType = KeyType.fromKey(pub).toString()
        val blob = Buffer.PlainBuffer().putPublicKey(pub).compactData
        val label = name.trim().ifEmpty { "kunci-impor" }
        val publicLine = "$keyType ${Base64.encodeToString(blob, Base64.NO_WRAP)} $label"
        val record = persist(label, keyType, publicLine, blob, pem)
        if (!passphrase.isNullOrEmpty()) store.put("sshkey:${record.id}:pass", passphrase)
        return record
    }

    fun privatePem(id: String): String =
        store.get("sshkey:$id") ?: throw OnyxException("key_missing", "Kunci privat tidak ditemukan")

    fun provider(client: SSHClient, id: String): KeyProvider {
        val pem = privatePem(id)
        val pass = store.get("sshkey:$id:pass")
        val finder = pass?.let { PasswordUtils.createOneOff(it.toCharArray()) }
        return client.loadKeys(pem, null, finder)
    }

    fun delete(id: String) {
        dao.deleteKey(id)
        store.remove("sshkey:$id")
        store.remove("sshkey:$id:pass")
    }

    private fun persist(
        name: String,
        type: String,
        publicLine: String,
        publicBlob: ByteArray,
        pem: String
    ): SshKeyRecord {
        val id = UUID.randomUUID().toString()
        val fingerprint = "SHA256:" + Base64.encodeToString(
            Crypto.sha256(publicBlob),
            Base64.NO_WRAP or Base64.NO_PADDING
        )
        val record = SshKeyRecord(id, name, type, publicLine, fingerprint, System.currentTimeMillis())
        store.put("sshkey:$id", pem)
        dao.insertKey(record)
        return record
    }

    private fun encodePoint(key: ECPublicKey, fieldBytes: Int): ByteArray {
        val x = fixed(key.w.affineX, fieldBytes)
        val y = fixed(key.w.affineY, fieldBytes)
        return byteArrayOf(4) + x + y
    }

    private fun fixed(value: BigInteger, size: Int): ByteArray {
        val raw = value.toByteArray()
        val stripped = if (raw.size > size && raw[0].toInt() == 0) raw.copyOfRange(raw.size - size, raw.size) else raw
        if (stripped.size >= size) return stripped
        return ByteArray(size - stripped.size) + stripped
    }

    private fun openSshPrivatePem(publicBlob: ByteArray, privateSection: ByteArray, comment: String): String {
        val check = random.nextInt()
        val inner = Wire().int(check).int(check).raw(privateSection).string(comment).bytes()
        val padded = ByteArrayOutputStream()
        padded.write(inner)
        var pad = 1
        while (padded.size() % 8 != 0) {
            padded.write(pad)
            pad++
        }
        val body = Wire()
            .raw("openssh-key-v1".toByteArray(Charsets.US_ASCII))
            .raw(byteArrayOf(0))
            .string("none")
            .string("none")
            .string(ByteArray(0))
            .int(1)
            .string(publicBlob)
            .string(padded.toByteArray())
            .bytes()
        val encoded = Base64.encodeToString(body, Base64.NO_WRAP)
        val sb = StringBuilder("-----BEGIN OPENSSH PRIVATE KEY-----\n")
        var i = 0
        while (i < encoded.length) {
            sb.append(encoded, i, minOf(i + 70, encoded.length)).append('\n')
            i += 70
        }
        sb.append("-----END OPENSSH PRIVATE KEY-----\n")
        return sb.toString()
    }
}
