package com.onyx.terminal.system

import android.os.SystemClock
import android.system.Os
import android.system.OsConstants
import com.onyx.terminal.util.OnyxException
import java.io.File

class ProcessManager {
    private data class Sample(val jiffies: Long, val wall: Long)

    private val previous = HashMap<Int, Sample>()
    private val ticks: Long = try {
        Os.sysconf(OsConstants._SC_CLK_TCK).takeIf { it > 0 } ?: 100L
    } catch (_: Exception) {
        100L
    }
    private val pageKb: Long = try {
        Os.sysconf(OsConstants._SC_PAGESIZE) / 1024
    } catch (_: Exception) {
        4L
    }
    private val myUid = android.os.Process.myUid()

    fun list(): List<Map<String, Any?>> {
        val now = SystemClock.elapsedRealtime()
        val dirs = File("/proc").listFiles { f -> f.isDirectory && f.name.all { it.isDigit() } } ?: emptyArray()
        val seen = HashSet<Int>()
        val out = ArrayList<Map<String, Any?>>()
        for (dir in dirs) {
            val pid = dir.name.toIntOrNull() ?: continue
            val stat = try {
                File(dir, "stat").readText()
            } catch (_: Exception) {
                continue
            }
            val open = stat.indexOf('(')
            val close = stat.lastIndexOf(')')
            if (open < 0 || close < open) continue
            val comm = stat.substring(open + 1, close)
            val rest = stat.substring(close + 2).split(' ')
            if (rest.size < 22) continue
            val state = rest[0]
            val ppid = rest[1].toIntOrNull() ?: 0
            val utime = rest[11].toLongOrNull() ?: 0L
            val stime = rest[12].toLongOrNull() ?: 0L
            val threads = rest[17].toIntOrNull() ?: 1
            val rssPages = rest[21].toLongOrNull() ?: 0L
            val jiffies = utime + stime
            seen.add(pid)
            var cpu = 0.0
            val before = previous[pid]
            if (before != null && now > before.wall) {
                val seconds = (now - before.wall) / 1000.0
                cpu = ((jiffies - before.jiffies) / ticks.toDouble() / seconds * 100.0).coerceAtLeast(0.0)
            }
            previous[pid] = Sample(jiffies, now)
            val cmdline = try {
                File(dir, "cmdline").readText().replace('\u0000', ' ').trim()
            } catch (_: Exception) {
                ""
            }
            val uid = try {
                File(dir, "status").useLines { lines ->
                    lines.firstOrNull { it.startsWith("Uid:") }?.substringAfter(':')?.trim()
                        ?.split(Regex("\\s+"))?.firstOrNull()?.toIntOrNull() ?: -1
                }
            } catch (_: Exception) {
                -1
            }
            out.add(
                mapOf(
                    "pid" to pid,
                    "ppid" to ppid,
                    "name" to comm,
                    "cmd" to cmdline.ifEmpty { comm },
                    "state" to state,
                    "threads" to threads,
                    "rssKb" to rssPages * pageKb,
                    "cpu" to cpu,
                    "uid" to uid,
                    "own" to (uid == myUid)
                )
            )
        }
        previous.keys.retainAll(seen)
        return out
    }

    fun signal(pid: Int, signal: Int) {
        if (pid <= 1) throw OnyxException("forbidden", "PID $pid tidak boleh dikirimi sinyal")
        if (pid == android.os.Process.myPid() && (signal == 9 || signal == 15)) {
            throw OnyxException("forbidden", "Menghentikan proses Onyx sendiri dari sini dinonaktifkan")
        }
        try {
            Os.kill(pid, signal)
        } catch (error: android.system.ErrnoException) {
            val reason = when (error.errno) {
                OsConstants.EPERM -> "Tidak diizinkan. Android hanya mengizinkan sinyal ke proses milik aplikasi ini."
                OsConstants.ESRCH -> "Proses sudah tidak ada"
                else -> error.message ?: "Gagal mengirim sinyal"
            }
            throw OnyxException("signal_failed", reason, error)
        }
    }
}
