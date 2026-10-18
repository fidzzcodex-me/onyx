package com.onyx.terminal.terminal

import android.os.ParcelFileDescriptor
import com.onyx.terminal.util.Limits
import com.onyx.terminal.util.Logger
import com.onyx.terminal.util.OnyxException
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException

interface SessionListener {
    fun onData(id: Int, data: ByteArray)
    fun onExit(id: Int, code: Int)
    fun onTitle(id: Int, title: String)
    fun onCwd(id: Int, path: String)
    fun onBell(id: Int)
    fun onCommandFinished(id: Int, elapsedMs: Long)
}

interface TerminalSession {
    val id: Int
    val kind: String
    var title: String
    val isAlive: Boolean
    val cwd: String?
    val watcher: CommandWatcher
    fun write(data: ByteArray)
    fun resize(rows: Int, cols: Int)
    fun kill()
    fun backlog(): ByteArray
}

class ShellSession(
    override val id: Int,
    private val spec: LaunchSpec,
    private val listener: SessionListener
) : TerminalSession {
    override val kind: String = "local"
    override var title: String = spec.title

    @Volatile
    private var alive = false

    @Volatile
    private var pid = -1

    @Volatile
    private var master: ParcelFileDescriptor? = null

    private var input: FileInputStream? = null
    private var output: FileOutputStream? = null
    private val writeLock = Any()
    private val ring = RingBuffer(Limits.SCROLLBACK_BYTES)
    private val batcher = OutputBatcher { listener.onData(id, it) }

    override val watcher = CommandWatcher { listener.onCommandFinished(id, it) }

    private val emulator = TerminalEmulator(object : TerminalEmulator.Events {
        override fun onTitle(title: String) {
            this@ShellSession.title = title
            listener.onTitle(id, title)
        }

        override fun onCwd(path: String) {
            listener.onCwd(id, path)
        }

        override fun onBell() {
            listener.onBell(id)
        }
    })

    override val isAlive: Boolean get() = alive
    override val cwd: String? get() = emulator.cwd

    fun start(rows: Int, cols: Int) {
        val result = NativePty.open(
            spec.command,
            spec.args.toTypedArray(),
            spec.env.toTypedArray(),
            spec.cwd,
            rows,
            cols
        ) ?: throw OnyxException("pty_failed", "Gagal membuat pseudo-terminal untuk ${spec.command}")
        val fd = result[0]
        pid = result[1]
        val descriptor = ParcelFileDescriptor.adoptFd(fd)
        master = descriptor
        input = FileInputStream(descriptor.fileDescriptor)
        output = FileOutputStream(descriptor.fileDescriptor)
        alive = true

        val reader = Thread({ readLoop() }, "onyx-pty-read-$id")
        reader.isDaemon = true
        reader.start()

        val waiter = Thread({
            val code = NativeExec.waitFor(pid)
            alive = false
            try {
                reader.join(800)
            } catch (_: InterruptedException) {
            }
            batcher.flush()
            watcher.cancel()
            try {
                master?.close()
            } catch (_: IOException) {
            }
            master = null
            listener.onExit(id, code)
        }, "onyx-pty-wait-$id")
        waiter.isDaemon = true
        waiter.start()
    }

    private fun readLoop() {
        val buffer = ByteArray(8192)
        val stream = input ?: return
        try {
            while (true) {
                val count = stream.read(buffer)
                if (count <= 0) break
                ring.write(buffer, count)
                emulator.feed(buffer, count)
                batcher.append(buffer, count)
                watcher.onOutput()
            }
        } catch (_: IOException) {
        } catch (error: Exception) {
            Logger.w("shell", "Pembacaan PTY berhenti", error)
        }
    }

    override fun write(data: ByteArray) {
        if (!alive) return
        watcher.onInput(data)
        synchronized(writeLock) {
            try {
                output?.write(data)
                output?.flush()
            } catch (_: IOException) {
            }
        }
    }

    override fun resize(rows: Int, cols: Int) {
        val descriptor = master ?: return
        if (rows <= 0 || cols <= 0) return
        NativePty.setSize(descriptor.fd, rows, cols, 0, 0)
    }

    override fun kill() {
        val target = pid
        if (target > 1) {
            NativeExec.signal(target, 1, true)
            NativeExec.signal(target, 15, true)
            val killer = Thread({
                try {
                    Thread.sleep(1500)
                } catch (_: InterruptedException) {
                }
                if (NativeExec.isAlive(target) == 1) NativeExec.signal(target, 9, true)
            }, "onyx-pty-kill-$id")
            killer.isDaemon = true
            killer.start()
        }
    }

    override fun backlog(): ByteArray = ring.snapshot()
}
