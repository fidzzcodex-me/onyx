package com.onyx.terminal.terminal

import android.content.Context
import android.os.Build
import android.system.Os
import com.onyx.terminal.util.Logger
import java.io.File

data class LaunchSpec(
    val command: String,
    val args: List<String>,
    val env: List<String>,
    val cwd: String,
    val title: String
)

class Bootstrap(private val context: Context) {
    val home: File = File(context.filesDir, "home")
    val prefix: File = File(context.filesDir, "usr")
    val binDir: File = File(prefix, "bin")
    private val tmpDir: File = File(context.cacheDir, "tmp")

    val busybox: File?
        get() {
            val candidate = File(context.applicationInfo.nativeLibraryDir, "libbusybox.so")
            return if (candidate.exists() && candidate.canExecute()) candidate else null
        }

    fun ensure() {
        home.mkdirs()
        File(home, "logs").mkdirs()
        File(home, ".config/onyx").mkdirs()
        binDir.mkdirs()
        tmpDir.mkdirs()
        copyAsset("assets/shell/bashrc", File(home, ".bashrc"))
        copyAsset("assets/shell/profile", File(home, ".profile"))
        val defaults = try {
            context.assets.list("flutter_assets/assets/default_config") ?: emptyArray()
        } catch (_: Exception) {
            emptyArray()
        }
        for (name in defaults) {
            copyAsset("assets/default_config/$name", File(home, ".config/onyx/$name"))
        }
        linkBusyboxApplets()
    }

    fun launchSpec(shellPref: String, cwd: String?, extraEnv: Map<String, String>, pathExtra: String?, title: String?): LaunchSpec {
        ensure()
        val resolved = resolveShell(shellPref)
        val workdir = cwd?.takeIf { File(it).isDirectory } ?: home.absolutePath
        val env = buildEnvironment(resolved.first, extraEnv, pathExtra)
        return LaunchSpec(resolved.first, resolved.second, env, workdir, title ?: File(resolved.first).name)
    }

    fun resolveShell(preference: String): Pair<String, List<String>> {
        val bb = busybox
        fun find(name: String): String? {
            val dirs = listOf(binDir.absolutePath, "/system/bin", "/system/xbin", "/vendor/bin")
            for (dir in dirs) {
                val file = File(dir, name)
                if (file.exists() && file.canExecute()) return file.absolutePath
            }
            return null
        }
        when (preference) {
            "bash" -> find("bash")?.let {
                return Pair(it, listOf("bash", "--rcfile", File(home, ".bashrc").absolutePath, "-i"))
            }
            "zsh" -> find("zsh")?.let { return Pair(it, listOf("zsh", "-i")) }
            "fish" -> find("fish")?.let { return Pair(it, listOf("fish", "-i")) }
            "sh" -> {
                return Pair("/system/bin/sh", listOf("sh"))
            }
        }
        if (bb != null) {
            return Pair(bb.absolutePath, listOf("busybox", "sh"))
        }
        find("bash")?.let {
            return Pair(it, listOf("bash", "--rcfile", File(home, ".bashrc").absolutePath, "-i"))
        }
        return Pair("/system/bin/sh", listOf("sh"))
    }

    fun availableShells(): List<String> {
        val out = mutableListOf("auto", "sh")
        for (name in listOf("bash", "zsh", "fish")) {
            val dirs = listOf(binDir.absolutePath, "/system/bin", "/system/xbin")
            if (dirs.any { File(it, name).canExecute() }) out.add(name)
        }
        return out
    }

    private fun buildEnvironment(shell: String, extra: Map<String, String>, pathExtra: String?): List<String> {
        val env = linkedMapOf<String, String>()
        val systemPath = System.getenv("PATH") ?: "/system/bin:/system/xbin"
        val nativeDir = context.applicationInfo.nativeLibraryDir
        val parts = mutableListOf(binDir.absolutePath)
        if (!pathExtra.isNullOrBlank()) parts.addAll(pathExtra.split(':').filter { it.isNotBlank() })
        parts.add(nativeDir)
        parts.add(systemPath)
        env["PATH"] = parts.joinToString(":")
        env["HOME"] = home.absolutePath
        env["TMPDIR"] = tmpDir.absolutePath
        env["PREFIX"] = prefix.absolutePath
        env["SHELL"] = shell
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = "en_US.UTF-8"
        env["ENV"] = File(home, ".profile").absolutePath
        env["EXTERNAL_STORAGE"] = "/sdcard"
        env["ONYX_VERSION"] = "1.0.0"
        env["ONYX_NATIVE_LIB_DIR"] = nativeDir
        env["ANDROID_ROOT"] = System.getenv("ANDROID_ROOT") ?: "/system"
        env["ANDROID_DATA"] = System.getenv("ANDROID_DATA") ?: "/data"
        System.getenv("BOOTCLASSPATH")?.let { env["BOOTCLASSPATH"] = it }
        System.getenv("ANDROID_RUNTIME_ROOT")?.let { env["ANDROID_RUNTIME_ROOT"] = it }
        System.getenv("ANDROID_ART_ROOT")?.let { env["ANDROID_ART_ROOT"] = it }
        System.getenv("ANDROID_I18N_ROOT")?.let { env["ANDROID_I18N_ROOT"] = it }
        System.getenv("ANDROID_TZDATA_ROOT")?.let { env["ANDROID_TZDATA_ROOT"] = it }
        for ((k, v) in extra) {
            if (k.matches(Regex("[A-Za-z_][A-Za-z0-9_]*"))) env[k] = v
        }
        return env.map { "${it.key}=${it.value}" }
    }

    private fun copyAsset(assetPath: String, target: File) {
        if (target.exists()) return
        try {
            context.assets.open("flutter_assets/$assetPath").use { input ->
                target.parentFile?.mkdirs()
                target.outputStream().use { input.copyTo(it) }
            }
        } catch (error: Exception) {
            Logger.w("bootstrap", "Aset $assetPath tidak dapat disalin", error)
        }
    }

    private fun linkBusyboxApplets() {
        val bb = busybox ?: return
        val stamp = File(prefix, ".busybox_stamp")
        val signature = "${bb.length()}:${bb.lastModified()}"
        if (stamp.exists() && stamp.readText() == signature) return
        try {
            val process = ProcessBuilder(bb.absolutePath, "--list").redirectErrorStream(true).start()
            val applets = process.inputStream.bufferedReader().readLines().map { it.trim() }.filter { it.isNotEmpty() }
            process.waitFor()
            for (name in applets) {
                val link = File(binDir, name)
                if (link.exists()) link.delete()
                try {
                    Os.symlink(bb.absolutePath, link.absolutePath)
                } catch (_: Exception) {
                }
            }
            stamp.writeText(signature)
        } catch (error: Exception) {
            Logger.w("bootstrap", "Gagal membuat tautan applet busybox", error)
        }
    }

    fun abi(): String = Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"
}
