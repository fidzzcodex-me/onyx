package com.onyx.terminal.plugins

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.onyx.terminal.system.NetworkTools
import com.onyx.terminal.system.SystemInfo
import com.onyx.terminal.util.Channels
import com.onyx.terminal.util.Disposable
import com.onyx.terminal.util.EventBridge
import com.onyx.terminal.util.Logger
import com.onyx.terminal.util.int
import com.onyx.terminal.util.map
import com.onyx.terminal.util.reply
import com.onyx.terminal.util.requireStr
import com.onyx.terminal.util.str
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap

class SystemPlugin(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, Disposable {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val channel = MethodChannel(messenger, Channels.SYSTEM)
    private val info = SystemInfo(context)
    private val tools = NetworkTools()
    private val handler = Handler(Looper.getMainLooper())
    private val cancelled = ConcurrentHashMap.newKeySet<String>()

    @Volatile
    private var intervalMs = 1000L

    private val tick = object : Runnable {
        override fun run() {
            if (!stream.active) return
            scope.launchSnapshot()
            handler.postDelayed(this, intervalMs)
        }
    }

    private val stream = EventBridge(
        messenger,
        Channels.SYSTEM_STREAM,
        listenHook = { handler.post(tick) },
        cancelHook = { handler.removeCallbacks(tick) }
    )

    init {
        channel.setMethodCallHandler(this)
    }

    private fun CoroutineScope.launchSnapshot() {
        launch(Dispatchers.IO) {
            try {
                val snapshot = HashMap<String, Any?>(info.snapshot())
                snapshot["type"] = "snapshot"
                stream.emit(snapshot)
            } catch (error: Exception) {
                Logger.w("system", "Snapshot gagal", error)
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "device" -> scope.reply(result) { info.device() }
            "snapshot" -> scope.reply(result) { info.snapshot() }
            "setInterval" -> {
                intervalMs = call.int("ms", 1000).coerceIn(500, 10_000).toLong()
                result.success(null)
            }
            "interfaces" -> scope.reply(result) { info.interfaces() }
            "dns" -> scope.reply(result) { tools.dns(call.requireStr("host")) }
            "ping" -> scope.reply(result) {
                tools.ping(
                    call.requireStr("host"),
                    call.int("count", 4),
                    call.int("timeoutMs", 3000),
                    call.int("port", 443)
                )
            }
            "portScan" -> scope.reply(result) {
                val id = call.requireStr("id")
                val ports = (call.argument<List<*>>("ports") ?: emptyList<Any>())
                    .mapNotNull { (it as? Number)?.toInt() }
                    .filter { it in 1..65535 }
                cancelled.remove(id)
                try {
                    tools.portScan(
                        call.requireStr("host"),
                        ports,
                        call.int("timeoutMs", 800),
                        { cancelled.contains(id) }
                    ) { done, total ->
                        stream.emit(mapOf("type" to "scan", "id" to id, "done" to done, "total" to total))
                    }
                } finally {
                    cancelled.remove(id)
                }
            }
            "cancelTool" -> {
                cancelled.add(call.requireStr("id"))
                result.success(null)
            }
            "http" -> scope.reply(result) {
                val headers = call.map("headers")?.mapValues { it.value?.toString() ?: "" } ?: emptyMap()
                tools.request(call.str("method") ?: "GET", call.requireStr("url"), headers, call.str("body"))
            }
            "publicIp" -> scope.reply(result) { tools.publicIp() }
            "logs" -> scope.reply(result) { Logger.tail(call.int("lines", 300)) }
            "clearLogs" -> {
                Logger.clear()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        handler.removeCallbacks(tick)
        channel.setMethodCallHandler(null)
        stream.dispose()
        scope.cancel()
    }
}
