package com.onyx.terminal.terminal

import android.content.Context
import android.os.Build
import com.onyx.terminal.util.Logger
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean

object RootfsManager {
    private const val ALPINE_VERSION = "3.20.3"
    private val busy = AtomicBoolean(false)

    @Volatile
    var lastError: String? = null

    fun rootDir(context: Context): File = File(context.filesDir, "alpine")

    fun marker(context: Context): File = File(rootDir(context), ".onyx_rootfs_ok")

    fun isReady(context: Context): Boolean {
        val root = rootDir(context)
        return marker(context).exists() && File(root, "bin/sh").canExecute()
    }

    fun prootBinary(context: Context): File? {
        val native = File(context.applicationInfo.nativeLibraryDir, "libproot.so")
        if (native.exists() && native.canExecute()) return native
        val fallback = File(context.filesDir, "usr/bin/proot")
        if (fallback.exists() && fallback.canExecute()) return fallback
        return null
    }

    fun alpineArch(): String {
        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
        return when {
            abi.startsWith("arm64") || abi == "aarch64" -> "aarch64"
            abi.startsWith("armeabi") || abi.startsWith("arm") -> "armhf"
            abi.startsWith("x86_64") -> "x86_64"
            abi.startsWith("x86") -> "x86"
            else -> "aarch64"
        }
    }

    fun tarballUrl(): String {
        val arch = alpineArch()
        return "https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/$arch/alpine-minirootfs-$ALPINE_VERSION-$arch.tar.gz"
    }

    fun status(context: Context): Map<String, Any?> {
        val root = rootDir(context)
        return mapOf(
            "ready" to isReady(context),
            "root" to root.absolutePath,
            "arch" to alpineArch(),
            "proot" to (prootBinary(context)?.absolutePath),
            "hasProot" to (prootBinary(context) != null),
            "busy" to busy.get(),
            "error" to lastError,
            "url" to tarballUrl()
        )
    }

    fun ensure(context: Context, onProgress: ((String, Int) -> Unit)? = null): Boolean {
        if (isReady(context)) return true
        if (!busy.compareAndSet(false, true)) return false
        lastError = null
        try {
            val root = rootDir(context)
            root.mkdirs()
            val tar = File(context.cacheDir, "alpine-minirootfs.tar.gz")
            onProgress?.invoke("download", 0)
            download(tarballUrl(), tar) { pct -> onProgress?.invoke("download", pct) }
            onProgress?.invoke("extract", 0)
            extractTarGz(tar, root)
            tar.delete()
            File(root, "etc/resolv.conf").writeText("nameserver 8.8.8.8\nnameserver 1.1.1.1\n")
            setupApkRepos(root)
            marker(context).writeText("$ALPINE_VERSION\n")
            onProgress?.invoke("done", 100)
            return true
        } catch (error: Exception) {
            lastError = error.message ?: error.javaClass.simpleName
            Logger.w("rootfs", "Bootstrap Alpine gagal", error)
            return false
        } finally {
            busy.set(false)
        }
    }

    private fun setupApkRepos(root: File) {
        val repos = File(root, "etc/apk/repositories")
        repos.parentFile?.mkdirs()
        val ver = "v3.20"
        repos.writeText(
            "https://dl-cdn.alpinelinux.org/alpine/$ver/main\n" +
                "https://dl-cdn.alpinelinux.org/alpine/$ver/community\n"
        )
    }

    private fun download(url: String, target: File, progress: (Int) -> Unit) {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 30_000
        conn.readTimeout = 120_000
        conn.instanceFollowRedirects = true
        conn.connect()
        if (conn.responseCode !in 200..299) {
            throw IllegalStateException("HTTP ${conn.responseCode} for $url")
        }
        val total = conn.contentLengthLong
        target.parentFile?.mkdirs()
        conn.inputStream.use { input ->
            FileOutputStream(target).use { output ->
                val buf = ByteArray(64 * 1024)
                var done = 0L
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    output.write(buf, 0, n)
                    done += n
                    if (total > 0) progress(((done * 100) / total).toInt().coerceIn(0, 99))
                }
            }
        }
        progress(100)
    }

    private fun extractTarGz(archive: File, dest: File) {
        dest.mkdirs()
        val pb = ProcessBuilder(
            "tar", "-xzf", archive.absolutePath, "-C", dest.absolutePath
        ).redirectErrorStream(true)
        val proc = pb.start()
        val log = proc.inputStream.bufferedReader().readText()
        val code = proc.waitFor()
        if (code != 0) {
            throw IllegalStateException("tar extract failed ($code): ${log.take(500)}")
        }
    }

    fun prootArgs(context: Context, shell: String = "/bin/sh"): Pair<String, List<String>>? {
        val proot = prootBinary(context) ?: return null
        if (!isReady(context)) return null
        val root = rootDir(context).absolutePath
        val args = mutableListOf(
            "proot",
            "--link2symlink",
            "-0",
            "-r", root,
            "-b", "/dev",
            "-b", "/proc",
            "-b", "/sys",
            "-b", "/sdcard:/sdcard",
            "-b", "/storage:/storage",
            "-b", "${context.filesDir.absolutePath}/home:/home/onyx",
            "-w", "/root"
        )
        args.add(shell)
        args.add("-l")
        return Pair(proot.absolutePath, args)
    }
}
