package com.onyx.terminal.terminal

class RingBuffer(private val capacity: Int) {
    private val data = ByteArray(capacity)
    private var start = 0
    private var size = 0
    private val lock = Any()

    fun write(source: ByteArray, length: Int) {
        synchronized(lock) {
            if (length >= capacity) {
                System.arraycopy(source, length - capacity, data, 0, capacity)
                start = 0
                size = capacity
                return
            }
            for (i in 0 until length) {
                val index = (start + size) % capacity
                data[index] = source[i]
                if (size < capacity) {
                    size++
                } else {
                    start = (start + 1) % capacity
                }
            }
        }
    }

    fun snapshot(): ByteArray {
        synchronized(lock) {
            val out = ByteArray(size)
            for (i in 0 until size) {
                out[i] = data[(start + i) % capacity]
            }
            return out
        }
    }

    fun clear() {
        synchronized(lock) {
            start = 0
            size = 0
        }
    }
}
