package com.onyx.terminal.terminal

import android.content.Context
import com.onyx.terminal.service.NotificationHelper
import com.onyx.terminal.service.TerminalService
import com.onyx.terminal.sftp.ConnectionManager
import com.onyx.terminal.util.EventBridge
import com.onyx.terminal.util.Logger
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

object NativePty {
    init {
        System.loadLibrary("onyxnative")
    }

    external fun open(
        command: String,
        args: Array<String>,
        env: Array<String>,
        cwd: String,
        rows: Int,
        cols: Int
    ): IntArray?

    external fun setSize(fd: Int, rows: Int, cols: Int, pixelWidth: Int, pixelHeight: Int)
}

object NativeExec {
    init {
        System.loadLibrary("onyxnative")
    }

    external fun waitFor(pid: Int): Int

    external fun signal(pid: Int, sig: Int, group: Boolean): Int

    external fun isAlive(pid: Int): Int
}

object PtyManager : SessionListener {
    private val sessions = ConcurrentHashMap<Int, TerminalSession>()
    private val counter = AtomicInteger(0)
    private lateinit var appContext: Context

    @Volatile
    var events: EventBridge? = null

    @Volatile
    var appForeground: Boolean = true

    @Volatile
    var visibleSessionId: Int = -1

    @Volatile
    var bellEnabled: Boolean = true

    @Volatile
    var bellThresholdMs: Long = 10_000L

    fun init(context: Context) {
        appContext = context.applicationContext
    }

    fun startLocal(
        context: Context,
        shell: String,
        cwd: String?,
        env: Map<String, String>,
        pathExtra: String?,
        title: String?,
        rows: Int,
        cols: Int
    ): TerminalSession {
        init(context)
        val spec = Bootstrap(context).launchSpec(shell, cwd, env, pathExtra, title)
        val id = counter.incrementAndGet()
        val session = ShellSession(id, spec, this)
        configure(session)
        session.start(rows, cols)
        register(session)
        return session
    }

    fun startSsh(
        context: Context,
        manager: ConnectionManager,
        profileId: String,
        rows: Int,
        cols: Int
    ): TerminalSession {
        init(context)
        val profile = manager.profile(profileId)
        val id = counter.incrementAndGet()
        val label = "${profile.username}@${profile.host}"
        val session = SshShellSession(id, label, { manager.openSsh(profileId) }, this)
        configure(session)
        register(session)
        session.start(rows, cols)
        return session
    }

    fun get(id: Int): TerminalSession? = sessions[id]

    fun all(): List<TerminalSession> = sessions.values.sortedBy { it.id }

    fun kill(id: Int) {
        sessions[id]?.kill()
    }

    fun killAll() {
        for (session in sessions.values) session.kill()
    }

    private fun configure(session: TerminalSession) {
        session.watcher.enabled = bellEnabled
        session.watcher.thresholdMs = bellThresholdMs
    }

    fun applyBellSettings() {
        for (session in sessions.values) configure(session)
    }

    private fun register(session: TerminalSession) {
        sessions[session.id] = session
        TerminalService.sync(appContext, sessions.size)
    }

    override fun onData(id: Int, data: ByteArray) {
        events?.emit(mapOf("type" to "data", "id" to id, "data" to data))
    }

    override fun onExit(id: Int, code: Int) {
        sessions.remove(id)
        events?.emit(mapOf("type" to "exit", "id" to id, "code" to code))
        TerminalService.sync(appContext, sessions.size)
        Logger.d("pty", "Sesi $id selesai dengan kode $code")
    }

    override fun onTitle(id: Int, title: String) {
        events?.emit(mapOf("type" to "title", "id" to id, "title" to title))
    }

    override fun onCwd(id: Int, path: String) {
        events?.emit(mapOf("type" to "cwd", "id" to id, "cwd" to path))
    }

    override fun onBell(id: Int) {
        events?.emit(mapOf("type" to "bell", "id" to id))
    }

    override fun onCommandFinished(id: Int, elapsedMs: Long) {
        events?.emit(mapOf("type" to "commandFinished", "id" to id, "elapsedMs" to elapsedMs))
        val hidden = !appForeground || visibleSessionId != id
        if (bellEnabled && hidden) {
            val title = sessions[id]?.title ?: "Terminal"
            NotificationHelper.alert(
                appContext,
                id,
                "Perintah selesai",
                "$title selesai setelah ${elapsedMs / 1000} detik"
            )
        }
    }
}
