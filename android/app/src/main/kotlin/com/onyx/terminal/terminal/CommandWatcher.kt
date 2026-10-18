package com.onyx.terminal.terminal

import com.onyx.terminal.util.MainThread

class CommandWatcher(private val onFinished: (Long) -> Unit) {
    @Volatile
    var thresholdMs: Long = 10_000L

    @Volatile
    var enabled: Boolean = true

    @Volatile
    private var startedAt = 0L

    private val idleCheck = Runnable { check() }

    fun onInput(data: ByteArray) {
        for (b in data) {
            val v = b.toInt()
            if (v == 13 || v == 10) {
                startedAt = System.currentTimeMillis()
                return
            }
        }
    }

    fun onOutput() {
        if (!enabled || startedAt == 0L) return
        MainThread.cancel(idleCheck)
        MainThread.postDelayed(IDLE_MS, idleCheck)
    }

    fun cancel() {
        MainThread.cancel(idleCheck)
        startedAt = 0L
    }

    private fun check() {
        val started = startedAt
        if (started == 0L || !enabled) return
        val elapsed = System.currentTimeMillis() - started
        if (elapsed >= thresholdMs) {
            startedAt = 0L
            onFinished(elapsed)
        }
    }

    companion object {
        private const val IDLE_MS = 1500L
    }
}
