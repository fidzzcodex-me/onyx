package com.onyx.terminal.terminal

import java.io.ByteArrayOutputStream

class AnsiParser(private val handler: Handler) {
    interface Handler {
        fun onBell()
        fun onOsc(code: Int, payload: String)
        fun onAltScreen(enabled: Boolean)
    }

    private enum class State { GROUND, ESC, CSI, OSC, OSC_ESC, STRING, STRING_ESC }

    private var state = State.GROUND
    private val osc = ByteArrayOutputStream()
    private val csi = StringBuilder()

    fun feed(data: ByteArray, length: Int) {
        for (i in 0 until length) {
            step(data[i].toInt() and 0xff)
        }
    }

    private fun step(b: Int) {
        when (state) {
            State.GROUND -> when (b) {
                0x07 -> handler.onBell()
                0x1b -> state = State.ESC
            }
            State.ESC -> when (b) {
                ']'.code -> {
                    osc.reset()
                    state = State.OSC
                }
                '['.code -> {
                    csi.setLength(0)
                    state = State.CSI
                }
                'P'.code, 'X'.code, '^'.code, '_'.code -> state = State.STRING
                else -> state = State.GROUND
            }
            State.CSI -> {
                if (b in 0x40..0x7e) {
                    finishCsi(b.toChar())
                    state = State.GROUND
                } else if (csi.length < MAX_CSI) {
                    csi.append(b.toChar())
                } else {
                    state = State.GROUND
                }
            }
            State.OSC -> when (b) {
                0x07 -> finishOsc()
                0x1b -> state = State.OSC_ESC
                else -> if (osc.size() < MAX_OSC) osc.write(b) else state = State.GROUND
            }
            State.OSC_ESC -> {
                if (b == '\\'.code) {
                    finishOsc()
                } else {
                    state = State.GROUND
                }
            }
            State.STRING -> if (b == 0x1b) state = State.STRING_ESC
            State.STRING_ESC -> state = if (b == '\\'.code) State.GROUND else State.STRING
        }
    }

    private fun finishOsc() {
        val text = String(osc.toByteArray(), Charsets.UTF_8)
        val split = text.indexOf(';')
        if (split > 0) {
            val code = text.substring(0, split).toIntOrNull()
            if (code != null) handler.onOsc(code, text.substring(split + 1))
        }
        osc.reset()
        state = State.GROUND
    }

    private fun finishCsi(last: Char) {
        if (last != 'h' && last != 'l') return
        val text = csi.toString()
        if (!text.startsWith("?")) return
        val enabled = last == 'h'
        for (part in text.substring(1).split(';')) {
            when (part) {
                "47", "1047", "1049" -> handler.onAltScreen(enabled)
            }
        }
    }

    companion object {
        private const val MAX_OSC = 4096
        private const val MAX_CSI = 64
    }
}
