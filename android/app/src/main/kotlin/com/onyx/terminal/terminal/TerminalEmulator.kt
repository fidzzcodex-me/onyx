package com.onyx.terminal.terminal

import java.net.URI
import java.net.URLDecoder

class TerminalEmulator(private val events: Events) {
    interface Events {
        fun onTitle(title: String)
        fun onCwd(path: String)
        fun onBell()
    }

    @Volatile
    var title: String = ""
        private set

    @Volatile
    var cwd: String? = null
        private set

    @Volatile
    var altScreen: Boolean = false
        private set

    @Volatile
    var lastOutputAt: Long = 0L
        private set

    private val parser = AnsiParser(object : AnsiParser.Handler {
        override fun onBell() {
            events.onBell()
        }

        override fun onOsc(code: Int, payload: String) {
            when (code) {
                0, 2 -> {
                    title = payload
                    events.onTitle(payload)
                }
                7 -> parseCwd(payload)
            }
        }

        override fun onAltScreen(enabled: Boolean) {
            altScreen = enabled
        }
    })

    fun feed(data: ByteArray, length: Int) {
        lastOutputAt = System.currentTimeMillis()
        parser.feed(data, length)
    }

    private fun parseCwd(payload: String) {
        try {
            val uri = URI(payload)
            val path = URLDecoder.decode(uri.rawPath ?: return, "UTF-8")
            cwd = path
            events.onCwd(path)
        } catch (_: Exception) {
        }
    }
}
