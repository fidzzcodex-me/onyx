package com.onyx.terminal.util

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.math.BigInteger
import java.security.MessageDigest

class OnyxException(val code: String, message: String, cause: Throwable? = null) :
    Exception(message, cause)

interface Disposable {
    fun dispose()
}

object MainThread {
    private val handler = Handler(Looper.getMainLooper())

    fun post(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else handler.post(block)
    }

    fun postDelayed(delayMs: Long, block: Runnable) {
        handler.postDelayed(block, delayMs)
    }

    fun cancel(block: Runnable) {
        handler.removeCallbacks(block)
    }
}

fun MethodCall.str(key: String): String? = argument<String>(key)

fun MethodCall.requireStr(key: String): String =
    argument<String>(key) ?: throw OnyxException("bad_args", "Argumen '$key' wajib diisi")

fun MethodCall.int(key: String, default: Int = 0): Int =
    (argument<Any>(key) as? Number)?.toInt() ?: default

fun MethodCall.long(key: String, default: Long = 0L): Long =
    (argument<Any>(key) as? Number)?.toLong() ?: default

fun MethodCall.bool(key: String, default: Boolean = false): Boolean =
    argument<Boolean>(key) ?: default

fun MethodCall.strList(key: String): List<String> {
    val raw = argument<List<*>>(key) ?: return emptyList()
    return raw.mapNotNull { it as? String }
}

fun MethodCall.map(key: String): Map<String, Any?>? {
    val raw = argument<Map<*, *>>(key) ?: return null
    return raw.entries.associate { it.key.toString() to it.value }
}

fun MethodCall.bytes(key: String): ByteArray? = argument<ByteArray>(key)

fun Map<String, Any?>.s(key: String): String? = this[key] as? String

fun Map<String, Any?>.i(key: String, default: Int = 0): Int =
    (this[key] as? Number)?.toInt() ?: default

fun Map<String, Any?>.b(key: String, default: Boolean = false): Boolean =
    this[key] as? Boolean ?: default

fun CoroutineScope.reply(
    result: MethodChannel.Result,
    dispatcher: CoroutineDispatcher = Dispatchers.IO,
    block: suspend () -> Any?
): Job = launch(dispatcher) {
    try {
        val value = block()
        val out = if (value == Unit) null else value
        withContext(Dispatchers.Main) { result.success(out) }
    } catch (cancel: CancellationException) {
        throw cancel
    } catch (error: OnyxException) {
        withContext(Dispatchers.Main) { result.error(error.code, error.message, null) }
    } catch (error: Throwable) {
        Logger.w("channel", error.message ?: error.javaClass.simpleName, error)
        withContext(Dispatchers.Main) {
            result.error("internal", error.message ?: error.javaClass.simpleName, null)
        }
    }
}

class EventBridge(
    messenger: BinaryMessenger,
    name: String,
    private val listenHook: (() -> Unit)? = null,
    private val cancelHook: (() -> Unit)? = null
) : EventChannel.StreamHandler, Disposable {
    @Volatile
    private var sink: EventChannel.EventSink? = null
    private val channel = EventChannel(messenger, name)

    init {
        channel.setStreamHandler(this)
    }

    val active: Boolean get() = sink != null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        listenHook?.invoke()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        cancelHook?.invoke()
    }

    fun emit(event: Any?) {
        val target = sink ?: return
        MainThread.post { target.success(event) }
    }

    override fun dispose() {
        sink = null
        channel.setStreamHandler(null)
    }
}

fun ByteArray.toHex(): String {
    val chars = "0123456789abcdef"
    val out = StringBuilder(size * 2)
    for (b in this) {
        val v = b.toInt() and 0xff
        out.append(chars[v ushr 4]).append(chars[v and 0x0f])
    }
    return out.toString()
}

fun hexToBytes(hex: String): ByteArray {
    val clean = hex.replace(" ", "").replace(":", "")
    if (clean.length % 2 != 0) throw OnyxException("bad_hex", "Panjang heksadesimal harus genap")
    val out = ByteArray(clean.length / 2)
    for (i in out.indices) {
        val hi = Character.digit(clean[i * 2], 16)
        val lo = Character.digit(clean[i * 2 + 1], 16)
        if (hi < 0 || lo < 0) throw OnyxException("bad_hex", "Karakter heksadesimal tidak valid")
        out[i] = ((hi shl 4) or lo).toByte()
    }
    return out
}

fun modeToString(mode: Int, isDir: Boolean, isLink: Boolean): String {
    val sb = StringBuilder(10)
    sb.append(if (isLink) 'l' else if (isDir) 'd' else '-')
    val bits = intArrayOf(0x100, 0x80, 0x40, 0x20, 0x10, 0x8, 0x4, 0x2, 0x1)
    val symbols = charArrayOf('r', 'w', 'x', 'r', 'w', 'x', 'r', 'w', 'x')
    for (i in bits.indices) {
        sb.append(if (mode and bits[i] != 0) symbols[i] else '-')
    }
    if (mode and 0x800 != 0) sb.setCharAt(3, if (mode and 0x40 != 0) 's' else 'S')
    if (mode and 0x400 != 0) sb.setCharAt(6, if (mode and 0x8 != 0) 's' else 'S')
    if (mode and 0x200 != 0) sb.setCharAt(9, if (mode and 0x1 != 0) 't' else 'T')
    return sb.toString()
}

fun digestHex(algorithm: String, data: ByteArray): String =
    MessageDigest.getInstance(algorithm).digest(data).toHex()

fun BigInteger.toSshMpint(): ByteArray = if (signum() == 0) ByteArray(0) else toByteArray()

fun String.expandHome(home: String): String =
    if (this == "~") home else if (startsWith("~/")) home + substring(1) else this
