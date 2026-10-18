package com.onyx.terminal.plugins

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.onyx.terminal.system.ProcessManager
import com.onyx.terminal.util.Channels
import com.onyx.terminal.util.Disposable
import com.onyx.terminal.util.EventBridge
import com.onyx.terminal.util.int
import com.onyx.terminal.util.reply
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class ProcessPlugin(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, Disposable {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val channel = MethodChannel(messenger, Channels.PROCESS)
    private val manager = ProcessManager()
    private val handler = Handler(Looper.getMainLooper())

    @Volatile
    private var intervalMs = 2000L

    private lateinit var stream: EventBridge

    private val tick = object : Runnable {
        override fun run() {
            if (!::stream.isInitialized || !stream.active) return
            scope.launch {
                try {
                    stream.emit(mapOf("type" to "processes", "items" to manager.list()))
                } catch (_: Exception) {
                }
            }
            handler.postDelayed(this, intervalMs)
        }
    }

    init {
        stream = EventBridge(
            messenger,
            Channels.PROCESS_STREAM,
            listenHook = { handler.post(tick) },
            cancelHook = { handler.removeCallbacks(tick) }
        )
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "list" -> scope.reply(result) { manager.list() }
            "signal" -> scope.reply(result) { manager.signal(call.int("pid", -1), call.int("signal", 15)) }
            "setInterval" -> {
                intervalMs = call.int("ms", 2000).coerceIn(1000, 10_000).toLong()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        handler.removeCallbacks(tick)
        channel.setMethodCallHandler(null)
        if (::stream.isInitialized) stream.dispose()
        scope.cancel()
    }
}
