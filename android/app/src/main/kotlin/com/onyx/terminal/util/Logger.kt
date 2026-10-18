package com.onyx.terminal.util

import android.content.Context
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object Logger {
    private const val TAG = "Onyx"
    private const val MAX_BYTES = 512L * 1024L

    @Volatile
    private var file: File? = null

    @Volatile
    private var verbose = false

    private val lock = Any()
    private val format = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US)

    fun init(context: Context, debuggable: Boolean) {
        verbose = debuggable
        val dir = File(context.filesDir, "logs")
        dir.mkdirs()
        file = File(dir, "onyx.log")
    }

    fun d(tag: String, message: String) {
        if (!verbose) return
        Log.d(TAG, "$tag: $message")
        append("D", tag, message)
    }

    fun i(tag: String, message: String) {
        if (verbose) Log.i(TAG, "$tag: $message")
        append("I", tag, message)
    }

    fun w(tag: String, message: String, error: Throwable? = null) {
        if (verbose) Log.w(TAG, "$tag: $message", error)
        append("W", tag, message + describe(error))
    }

    fun e(tag: String, message: String, error: Throwable? = null) {
        if (verbose) Log.e(TAG, "$tag: $message", error)
        append("E", tag, message + describe(error))
    }

    fun tail(maxLines: Int): List<String> {
        val target = file ?: return emptyList()
        return synchronized(lock) {
            try {
                if (!target.exists()) emptyList() else target.readLines().takeLast(maxLines)
            } catch (_: Exception) {
                emptyList()
            }
        }
    }

    fun clear() {
        val target = file ?: return
        synchronized(lock) {
            try {
                target.writeText("")
            } catch (_: Exception) {
            }
        }
    }

    private fun describe(error: Throwable?): String {
        if (error == null) return ""
        return " [" + error.javaClass.simpleName + "]"
    }

    private fun append(level: String, tag: String, message: String) {
        val target = file ?: return
        synchronized(lock) {
            try {
                if (target.length() > MAX_BYTES) {
                    val keep = target.readLines().takeLast(400)
                    target.writeText(keep.joinToString("\n", postfix = "\n"))
                }
                target.appendText("${format.format(Date())} $level/$tag: $message\n")
            } catch (_: Exception) {
            }
        }
    }
}
