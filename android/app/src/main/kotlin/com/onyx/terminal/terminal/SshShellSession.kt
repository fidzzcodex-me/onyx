package com.onyx.terminal.terminal

import com.onyx.terminal.sftp.OpenedSsh
import com.onyx.terminal.util.Limits
import com.onyx.terminal.util.Logger
import net.schmizz.sshj.connection.channel.direct.Session
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

class SshShellSession(
    override val id: Int,
    override var title: String,
    private val opener: () -> OpenedSsh,
    private val listener: SessionListener
) : TerminalSession {
    override val kind: String = "ssh"

    @Volatile
    private var alive = true

    @Volatile
    private var shell: Session.Shell? = null

    @Volatile
    private var opened: OpenedSsh? = null

    @Volatile
    private var pendingRows = 24

    @Volatile
    private var pendingCols = 80

    private var stdin: OutputStream? = null
    private val ring = RingBuffer(Limits.SCROLLBACK_BYTES)
    private val batcher = OutputBatcher { listener.onData(id, it) }
    private val writeLock = Any()
    private val earlyInput = java.io.ByteArrayOutputStream()

    override val watcher = CommandWatcher { listener.onCommandFinished(id, it) }

    private val emulator = TerminalEmulator(object : TerminalEmulator.Events {
        override fun onTitle(title: String) {
            this@SshShellSession.title = title
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
        pendingRows = rows
        pendingCols = cols
        val thread = Thread({ run() }, "onyx-ssh-$id")
        thread.isDaemon = true
        thread.start()
    }

    private fun emitLocal(text: String) {
        val bytes = text.toByteArray(Charsets.UTF_8)
        ring.write(bytes, bytes.size)
        batcher.append(bytes, bytes.size)
    }

    private fun run() {
        var exitCode = 0
        try {
            emitLocal("Menghubungkan ke $title ...\r\n")
            val ssh = opener()
            opened = ssh
            val session = ssh.client.startSession()
            session.allocatePTY("xterm-256color", pendingCols, pendingRows, 0, 0, emptyMap())
            val started = session.startShell()
            shell = started
            val out = started.outputStream
            synchronized(writeLock) {
                stdin = out
                if (earlyInput.size() > 0) {
                    out.write(earlyInput.toByteArray())
                    out.flush()
                    earlyInput.reset()
                }
            }
            emitLocal("Terhubung.\r\n")
            readLoop(started.inputStream)
            exitCode = 0
        } catch (error: Exception) {
            Logger.w("ssh-shell", "Sesi SSH berakhir dengan galat", error)
            emitLocal("\r\n[Koneksi gagal: ${error.message ?: error.javaClass.simpleName}]\r\n")
            exitCode = 255
        } finally {
            alive = false
            synchronized(writeLock) {
                stdin = null
            }
            batcher.flush()
            watcher.cancel()
            closeQuietly()
            listener.onExit(id, exitCode)
        }
    }

    private fun readLoop(stream: InputStream) {
        val buffer = ByteArray(8192)
        try {
            while (alive) {
                val count = stream.read(buffer)
                if (count < 0) break
                if (count == 0) continue
                ring.write(buffer, count)
                emulator.feed(buffer, count)
                batcher.append(buffer, count)
                watcher.onOutput()
            }
        } catch (_: IOException) {
        }
    }

    override fun write(data: ByteArray) {
        if (!alive || data.isEmpty()) return
        watcher.onInput(data)
        synchronized(writeLock) {
            val out = stdin
            if (out == null) {
                earlyInput.write(data)
                return
            }
            try {
                out.write(data)
                out.flush()
            } catch (error: IOException) {
                Logger.w("ssh-shell", "Gagal menulis ke shell SSH ($id)", error)
            }
        }
    }

    override fun resize(rows: Int, cols: Int) {
        pendingRows = rows
        pendingCols = cols
        val active = shell ?: return
        try {
            active.changeWindowDimensions(cols, rows, 0, 0)
        } catch (_: Exception) {
        }
    }

    override fun kill() {
        alive = false
        closeQuietly()
    }

    override fun backlog(): ByteArray = ring.snapshot()

    private fun closeQuietly() {
        try {
            shell?.close()
        } catch (_: Exception) {
        }
        try {
            opened?.close()
        } catch (_: Exception) {
        }
    }
}
