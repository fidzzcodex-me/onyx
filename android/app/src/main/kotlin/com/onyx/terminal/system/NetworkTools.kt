package com.onyx.terminal.system

import com.onyx.terminal.util.OnyxException
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class NetworkTools {
    private val http = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    fun dns(host: String): Map<String, Any?> {
        val started = System.nanoTime()
        val addresses = try {
            InetAddress.getAllByName(host.trim())
        } catch (error: Exception) {
            throw OnyxException("dns_failed", "Tidak dapat meresolusi ${host.trim()}: ${error.message}", error)
        }
        return mapOf(
            "host" to host.trim(),
            "timeMs" to (System.nanoTime() - started) / 1_000_000.0,
            "addresses" to addresses.map {
                mapOf("address" to (it.hostAddress ?: ""), "ipv6" to (it is java.net.Inet6Address))
            }
        )
    }

    fun ping(host: String, count: Int, timeoutMs: Int, port: Int): Map<String, Any?> {
        val target = host.trim()
        val address = try {
            InetAddress.getByName(target)
        } catch (error: Exception) {
            throw OnyxException("dns_failed", "Tidak dapat meresolusi $target", error)
        }
        val times = ArrayList<Double>()
        var lost = 0
        for (i in 0 until count.coerceIn(1, 20)) {
            val started = System.nanoTime()
            try {
                Socket().use { it.connect(InetSocketAddress(address, port), timeoutMs) }
                times.add((System.nanoTime() - started) / 1_000_000.0)
            } catch (_: Exception) {
                lost++
            }
            if (i < count - 1) Thread.sleep(250)
        }
        return mapOf(
            "host" to target,
            "address" to (address.hostAddress ?: ""),
            "method" to "tcp:$port",
            "sent" to count.coerceIn(1, 20),
            "lost" to lost,
            "min" to (times.minOrNull() ?: -1.0),
            "max" to (times.maxOrNull() ?: -1.0),
            "avg" to (if (times.isEmpty()) -1.0 else times.average()),
            "samples" to times
        )
    }

    fun portScan(
        host: String,
        ports: List<Int>,
        timeoutMs: Int,
        isCancelled: () -> Boolean,
        onProgress: (Int, Int) -> Unit
    ): Map<String, Any?> {
        if (ports.isEmpty()) throw OnyxException("bad_args", "Daftar port kosong")
        if (ports.size > 2048) throw OnyxException("too_many", "Maksimal 2048 port per pemindaian")
        val address = try {
            InetAddress.getByName(host.trim())
        } catch (error: Exception) {
            throw OnyxException("dns_failed", "Tidak dapat meresolusi ${host.trim()}", error)
        }
        val open = ConcurrentLinkedQueue<Int>()
        val done = AtomicInteger(0)
        val pool = Executors.newFixedThreadPool(24)
        try {
            for (port in ports) {
                pool.execute {
                    if (isCancelled()) return@execute
                    try {
                        Socket().use { it.connect(InetSocketAddress(address, port), timeoutMs) }
                        open.add(port)
                    } catch (_: Exception) {
                    }
                    val finished = done.incrementAndGet()
                    if (finished % 16 == 0 || finished == ports.size) onProgress(finished, ports.size)
                }
            }
        } finally {
            pool.shutdown()
            pool.awaitTermination(10, TimeUnit.MINUTES)
        }
        return mapOf(
            "host" to host.trim(),
            "address" to (address.hostAddress ?: ""),
            "scanned" to done.get(),
            "open" to open.sorted(),
            "cancelled" to isCancelled()
        )
    }

    fun request(
        method: String,
        url: String,
        headers: Map<String, String>,
        body: String?
    ): Map<String, Any?> {
        val builder = try {
            Request.Builder().url(url)
        } catch (error: Exception) {
            throw OnyxException("bad_url", "URL tidak valid: $url", error)
        }
        headers.forEach { (key, value) -> builder.header(key, value) }
        val upper = method.uppercase()
        val contentType = headers.entries.firstOrNull { it.key.equals("content-type", true) }?.value
        val payload = if (upper == "GET" || upper == "HEAD") null else (body ?: "").toRequestBody(contentType?.toMediaTypeOrNull())
        builder.method(upper, payload)
        val started = System.nanoTime()
        try {
            http.newCall(builder.build()).execute().use { response ->
                val bytes = response.body?.let { responseBody ->
                    val source = responseBody.source()
                    source.request(MAX_BODY)
                    val data = source.buffer.snapshot().toByteArray()
                    if (data.size > MAX_BODY) data.copyOf(MAX_BODY.toInt()) else data
                } ?: ByteArray(0)
                val elapsed = (System.nanoTime() - started) / 1_000_000.0
                return mapOf(
                    "status" to response.code,
                    "message" to response.message,
                    "timeMs" to elapsed,
                    "protocol" to response.protocol.toString(),
                    "headers" to response.headers.toMultimap().mapValues { it.value.joinToString(", ") },
                    "body" to String(bytes, Charsets.UTF_8),
                    "truncated" to (bytes.size >= MAX_BODY)
                )
            }
        } catch (error: Exception) {
            throw OnyxException("request_failed", "Permintaan gagal: ${error.message}", error)
        }
    }

    fun publicIp(): String {
        val request = Request.Builder().url("https://api.ipify.org").build()
        try {
            http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) throw OnyxException("lookup_failed", "Layanan IP merespons ${response.code}")
                return response.body?.string()?.trim().orEmpty()
            }
        } catch (error: OnyxException) {
            throw error
        } catch (error: Exception) {
            throw OnyxException("lookup_failed", "Tidak dapat mengambil IP publik: ${error.message}", error)
        }
    }

    companion object {
        private const val MAX_BODY = 256L * 1024L
    }
}
