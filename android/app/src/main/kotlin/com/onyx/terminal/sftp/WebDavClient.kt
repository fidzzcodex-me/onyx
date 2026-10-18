package com.onyx.terminal.sftp

import android.net.Uri
import android.util.Xml
import com.onyx.terminal.db.ConnectionProfile
import com.onyx.terminal.util.OnyxException
import okhttp3.Credentials
import okhttp3.MediaType
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okio.BufferedSink
import org.xmlpull.v1.XmlPullParser
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.InetSocketAddress
import java.net.Proxy
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

class WebDavRemoteFs(
    private val profile: ConnectionProfile,
    private val password: String
) : RemoteFs {
    override val protocol: String = "webdav"
    private val tls: Boolean = profile.options.optBoolean("tls", true)
    private val origin: String = (if (tls) "https" else "http") + "://" + profile.host + ":" + profile.port
    private val authHeader: String = Credentials.basic(profile.username, password)
    private val http: OkHttpClient

    init {
        if (!tls && profile.host != "localhost" && profile.host != "127.0.0.1") {
            throw OnyxException("cleartext_blocked", "WebDAV tanpa TLS diblokir. Gunakan https.")
        }
        val builder = OkHttpClient.Builder()
            .connectTimeout(profile.timeoutSec.toLong(), TimeUnit.SECONDS)
            .readTimeout(profile.timeoutSec.toLong().coerceAtLeast(30), TimeUnit.SECONDS)
            .writeTimeout(profile.timeoutSec.toLong().coerceAtLeast(30), TimeUnit.SECONDS)
        if (profile.proxyType != "none" && !profile.proxyHost.isNullOrBlank()) {
            val type = if (profile.proxyType == "socks") Proxy.Type.SOCKS else Proxy.Type.HTTP
            builder.proxy(Proxy(type, InetSocketAddress.createUnresolved(profile.proxyHost, profile.proxyPort)))
        }
        http = builder.build()
        list(home())
    }

    private fun url(path: String): String = origin + Uri.encode(path, "/")

    private fun request(path: String): Request.Builder =
        Request.Builder().url(url(path)).header("Authorization", authHeader)

    private fun check(response: Response, vararg ok: Int): Response {
        if (response.code in ok) return response
        val code = response.code
        response.close()
        throw when (code) {
            401, 403 -> OnyxException("auth_failed", "WebDAV menolak kredensial (HTTP $code)")
            404 -> OnyxException("not_found", "Jalur tidak ditemukan di server (HTTP 404)")
            else -> OnyxException("webdav_error", "Server WebDAV merespons HTTP $code")
        }
    }

    override fun home(): String = profile.initialPath?.takeIf { it.isNotBlank() } ?: "/"

    override fun list(path: String): List<RemoteEntry> {
        val body = ("<?xml version=\"1.0\"?><d:propfind xmlns:d=\"DAV:\"><d:prop><d:displayname/>" +
            "<d:getcontentlength/><d:getlastmodified/><d:resourcetype/></d:prop></d:propfind>")
            .toRequestBody("application/xml".toMediaType())
        val call = http.newCall(request(path).method("PROPFIND", body).header("Depth", "1").build())
        check(call.execute(), 207, 200).use { response ->
            val text = response.body?.string().orEmpty()
            return parse(text, path)
        }
    }

    override fun stat(path: String): RemoteEntry? {
        val body = ("<?xml version=\"1.0\"?><d:propfind xmlns:d=\"DAV:\"><d:prop><d:getcontentlength/>" +
            "<d:getlastmodified/><d:resourcetype/></d:prop></d:propfind>")
            .toRequestBody("application/xml".toMediaType())
        return try {
            val call = http.newCall(request(path).method("PROPFIND", body).header("Depth", "0").build())
            check(call.execute(), 207, 200).use { response ->
                parse(response.body?.string().orEmpty(), path, includeSelf = true).firstOrNull()
            }
        } catch (_: Exception) {
            null
        }
    }

    override fun mkdir(path: String) {
        check(http.newCall(request(path).method("MKCOL", null).build()).execute(), 201, 405).close()
    }

    override fun delete(path: String, recursive: Boolean) {
        check(http.newCall(request(path).delete().build()).execute(), 200, 204, 404).close()
    }

    override fun rename(from: String, to: String) {
        val call = http.newCall(
            request(from).method("MOVE", null)
                .header("Destination", url(to))
                .header("Overwrite", "F")
                .build()
        )
        check(call.execute(), 201, 204).close()
    }

    override fun chmod(path: String, mode: Int) {
        throw OnyxException("unsupported", "WebDAV tidak mendukung perubahan izin")
    }

    override fun readBytes(path: String, maxBytes: Long): ByteArray {
        check(http.newCall(request(path).get().build()).execute(), 200).use { response ->
            val stream = response.body?.byteStream() ?: return ByteArray(0)
            val out = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(32 * 1024)
            while (true) {
                val count = stream.read(buffer)
                if (count < 0) break
                out.write(buffer, 0, count)
                if (out.size() > maxBytes) throw OnyxException("too_large", "Berkas melebihi batas baca")
            }
            return out.toByteArray()
        }
    }

    override fun writeBytes(path: String, data: ByteArray) {
        val body = data.toRequestBody("application/octet-stream".toMediaType())
        check(http.newCall(request(path).put(body).build()).execute(), 200, 201, 204).close()
    }

    override fun download(remote: String, local: File, offset: Long, progress: (Long) -> Unit) {
        val resumeAt = if (offset > 0 && local.exists() && local.length() == offset) offset else 0L
        local.parentFile?.mkdirs()
        val builder = request(remote).get()
        if (resumeAt > 0) builder.header("Range", "bytes=$resumeAt-")
        check(http.newCall(builder.build()).execute(), 200, 206).use { response ->
            val append = response.code == 206 && resumeAt > 0
            val stream = response.body?.byteStream() ?: return
            FileOutputStream(local, append).use { output ->
                val buffer = ByteArray(64 * 1024)
                var done = if (append) resumeAt else 0L
                while (true) {
                    val count = stream.read(buffer)
                    if (count < 0) break
                    output.write(buffer, 0, count)
                    done += count
                    progress(done)
                }
            }
        }
    }

    override fun upload(local: File, remote: String, offset: Long, progress: (Long) -> Unit) {
        val body = object : RequestBody() {
            override fun contentType(): MediaType? = "application/octet-stream".toMediaType()

            override fun contentLength(): Long = local.length()

            override fun writeTo(sink: BufferedSink) {
                FileInputStream(local).use { input ->
                    val buffer = ByteArray(64 * 1024)
                    var done = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        sink.write(buffer, 0, count)
                        done += count
                        progress(done)
                    }
                }
            }
        }
        check(http.newCall(request(remote).put(body).build()).execute(), 200, 201, 204).close()
    }

    override fun isAlive(): Boolean = true

    override fun close() {
        http.dispatcher.executorService.shutdown()
        http.connectionPool.evictAll()
    }

    private fun parse(xml: String, requested: String, includeSelf: Boolean = false): List<RemoteEntry> {
        val parser = Xml.newPullParser()
        parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, true)
        parser.setInput(xml.reader())
        val out = ArrayList<RemoteEntry>()
        val dateFormat = SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss zzz", Locale.US)
        dateFormat.timeZone = TimeZone.getTimeZone("GMT")
        var href = ""
        var display = ""
        var length = 0L
        var modified = 0L
        var collection = false
        var inResponse = false
        val requestedNorm = requested.trimEnd('/')
        var event = parser.eventType
        while (event != XmlPullParser.END_DOCUMENT) {
            if (event == XmlPullParser.START_TAG) {
                when (parser.name) {
                    "response" -> {
                        inResponse = true
                        href = ""
                        display = ""
                        length = 0L
                        modified = 0L
                        collection = false
                    }
                    "href" -> if (inResponse) href = Uri.decode(parser.nextText().trim())
                    "displayname" -> if (inResponse) display = parser.nextText().trim()
                    "getcontentlength" -> if (inResponse) length = parser.nextText().trim().toLongOrNull() ?: 0L
                    "getlastmodified" -> if (inResponse) {
                        modified = try {
                            dateFormat.parse(parser.nextText().trim())?.time ?: 0L
                        } catch (_: Exception) {
                            0L
                        }
                    }
                    "collection" -> if (inResponse) collection = true
                }
            } else if (event == XmlPullParser.END_TAG && parser.name == "response") {
                inResponse = false
                var path = href
                if (path.startsWith("http")) path = Uri.parse(path).path ?: path
                val norm = path.trimEnd('/')
                val isSelf = norm == requestedNorm || (norm.isEmpty() && requestedNorm.isEmpty())
                if (includeSelf || !isSelf) {
                    val name = display.ifEmpty { RemotePath.name(path) }
                    out.add(
                        RemoteEntry(
                            name = name,
                            path = if (collection) norm.ifEmpty { "/" } else path,
                            isDir = collection,
                            size = if (collection) 0L else length,
                            modified = modified,
                            mode = if (collection) "drwxr-xr-x" else "-rw-r--r--",
                            isLink = false
                        )
                    )
                }
            }
            event = parser.next()
        }
        return out
    }
}
