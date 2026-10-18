package com.onyx.terminal.plugins

import android.content.Context
import com.onyx.terminal.sftp.ConnectionManager
import com.onyx.terminal.terminal.Bootstrap
import com.onyx.terminal.terminal.PtyManager
import com.onyx.terminal.terminal.TerminalSession
import com.onyx.terminal.util.Channels
import com.onyx.terminal.util.Disposable
import com.onyx.terminal.util.EventBridge
import com.onyx.terminal.util.OnyxException
import com.onyx.terminal.util.bool
import com.onyx.terminal.util.bytes
import com.onyx.terminal.util.int
import com.onyx.terminal.util.long
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

class TerminalPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
    private val connections: ConnectionManager
) : MethodChannel.MethodCallHandler, Disposable {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val channel = MethodChannel(messenger, Channels.TERMINAL)
    private val stream = EventBridge(messenger, Channels.TERMINAL_STREAM)

    init {
        PtyManager.init(context)
        PtyManager.events = stream
        channel.setMethodCallHandler(this)
    }

    private fun describe(session: TerminalSession): Map<String, Any?> = mapOf(
        "id" to session.id,
        "kind" to session.kind,
        "title" to session.title,
        "alive" to session.isAlive,
        "cwd" to session.cwd
    )

    private fun require(id: Int): TerminalSession =
        PtyManager.get(id) ?: throw OnyxException("no_session", "Sesi terminal $id tidak ditemukan")

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> scope.reply(result) {
                val bootstrap = Bootstrap(context)
                bootstrap.ensure()
                mapOf(
                    "home" to bootstrap.home.absolutePath,
                    "hasBusybox" to (bootstrap.busybox != null),
                    "abi" to bootstrap.abi(),
                    "shells" to bootstrap.availableShells()
                )
            }
            "start" -> scope.reply(result) {
                val env = call.map("env")?.mapValues { it.value?.toString() ?: "" } ?: emptyMap()
                val session = PtyManager.startLocal(
                    context,
                    call.str("shell") ?: "auto",
                    call.str("cwd"),
                    env,
                    call.str("pathExtra"),
                    call.str("title"),
                    call.int("rows", 24),
                    call.int("cols", 80)
                )
                describe(session)
            }
            "startSsh" -> scope.reply(result) {
                val session = PtyManager.startSsh(
                    context,
                    connections,
                    call.requireStr("profileId"),
                    call.int("rows", 24),
                    call.int("cols", 80)
                )
                describe(session)
            }
            "write" -> {
                val data = call.bytes("data")
                val session = PtyManager.get(call.int("id", -1))
                if (data != null && session != null) session.write(data)
                result.success(null)
            }
            "resize" -> {
                PtyManager.get(call.int("id", -1))?.resize(call.int("rows", 24), call.int("cols", 80))
                result.success(null)
            }
            "kill" -> {
                PtyManager.kill(call.int("id", -1))
                result.success(null)
            }
            "killAll" -> {
                PtyManager.killAll()
                result.success(null)
            }
            "list" -> result.success(PtyManager.all().map { describe(it) })
            "attach" -> scope.reply(result) {
                val session = require(call.int("id", -1))
                describe(session) + mapOf("backlog" to session.backlog())
            }
            "setBell" -> {
                PtyManager.bellEnabled = call.bool("enabled", true)
                PtyManager.bellThresholdMs = call.long("thresholdMs", 10_000L)
                PtyManager.applyBellSettings()
                result.success(null)
            }
            "setVisible" -> {
                PtyManager.visibleSessionId = call.int("id", -1)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        PtyManager.events = null
        channel.setMethodCallHandler(null)
        stream.dispose()
        scope.cancel()
    }
}
