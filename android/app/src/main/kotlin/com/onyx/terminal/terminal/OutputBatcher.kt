package com.onyx.terminal.terminal

import com.onyx.terminal.util.Limits
import com.onyx.terminal.util.MainThread
import java.io.ByteArrayOutputStream

class OutputBatcher(private val sink: (ByteArray) -> Unit) {
    private val buffer = ByteArrayOutputStream()
    private val lock = Any()
    private var scheduled = false

    private val flushRunnable = Runnable { flush() }

    fun append(data: ByteArray, length: Int) {
        var shouldFlushNow = false
        synchronized(lock) {
            buffer.write(data, 0, length)
            if (buffer.size() >= Limits.OUTPUT_BATCH_MAX) {
                shouldFlushNow = true
            } else if (!scheduled) {
                scheduled = true
                MainThread.postDelayed(Limits.OUTPUT_BATCH_MS, flushRunnable)
            }
        }
        if (shouldFlushNow) flush()
    }

    fun flush() {
        val chunk: ByteArray
        synchronized(lock) {
            scheduled = false
            if (buffer.size() == 0) return
            chunk = buffer.toByteArray()
            buffer.reset()
        }
        sink(chunk)
    }
}
