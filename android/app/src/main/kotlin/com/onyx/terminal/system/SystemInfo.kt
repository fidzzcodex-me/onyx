package com.onyx.terminal.system

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.SystemClock
import android.os.StatFs
import java.io.File
import java.net.NetworkInterface

class SystemInfo(private val context: Context) {
    private var lastCpu: LongArray? = null
    private var lastRx = -1L
    private var lastTx = -1L
    private var lastNetTime = 0L
    private var cpuSource = "none"

    fun device(): Map<String, Any?> = mapOf(
        "manufacturer" to Build.MANUFACTURER,
        "model" to Build.MODEL,
        "brand" to Build.BRAND,
        "device" to Build.DEVICE,
        "board" to Build.BOARD,
        "hardware" to Build.HARDWARE,
        "androidVersion" to Build.VERSION.RELEASE,
        "sdk" to Build.VERSION.SDK_INT,
        "securityPatch" to (if (Build.VERSION.SDK_INT >= 23) Build.VERSION.SECURITY_PATCH else ""),
        "abis" to Build.SUPPORTED_ABIS.toList(),
        "cores" to Runtime.getRuntime().availableProcessors(),
        "kernel" to (System.getProperty("os.version") ?: ""),
        "fingerprint" to Build.FINGERPRINT,
        "cpuModel" to cpuModel()
    )

    private fun cpuModel(): String {
        return try {
            File("/proc/cpuinfo").readLines().firstOrNull {
                it.startsWith("Hardware") || it.startsWith("model name") || it.startsWith("Processor")
            }?.substringAfter(':')?.trim().orEmpty()
        } catch (_: Exception) {
            ""
        }
    }

    fun snapshot(): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        out["time"] = System.currentTimeMillis()
        out["uptimeMs"] = SystemClock.elapsedRealtime()
        out["cpu"] = cpu()
        out["memory"] = memory()
        out["storage"] = storage()
        out["battery"] = battery()
        out["network"] = network()
        return out
    }

    private fun cpu(): Map<String, Any?> {
        val cores = Runtime.getRuntime().availableProcessors()
        var percent = -1.0
        var source = "none"
        val current = readProcStat()
        val previous = lastCpu
        if (current != null) {
            source = "proc_stat"
            if (previous != null) {
                val idle = current[0] - previous[0]
                val total = current[1] - previous[1]
                if (total > 0) percent = ((total - idle) * 100.0 / total).coerceIn(0.0, 100.0)
            }
            lastCpu = current
        } else {
            val freq = frequencyLoad()
            if (freq >= 0) {
                percent = freq
                source = "cpufreq"
            }
        }
        cpuSource = source
        val frequencies = ArrayList<Long>()
        for (i in 0 until cores) {
            val value = readLong("/sys/devices/system/cpu/cpu$i/cpufreq/scaling_cur_freq")
            frequencies.add(if (value >= 0) value / 1000 else -1L)
        }
        val load = try {
            File("/proc/loadavg").readText().trim().split(' ').take(3).mapNotNull { it.toDoubleOrNull() }
        } catch (_: Exception) {
            emptyList()
        }
        return mapOf(
            "percent" to percent,
            "source" to source,
            "cores" to cores,
            "freqMhz" to frequencies,
            "load" to load
        )
    }

    private fun readProcStat(): LongArray? {
        return try {
            val line = File("/proc/stat").bufferedReader().use { it.readLine() } ?: return null
            if (!line.startsWith("cpu ")) return null
            val parts = line.trim().split(Regex("\\s+")).drop(1).mapNotNull { it.toLongOrNull() }
            if (parts.size < 4) return null
            val idle = parts[3] + parts.getOrElse(4) { 0L }
            val total = parts.take(8).sum()
            longArrayOf(idle, total)
        } catch (_: Exception) {
            null
        }
    }

    private fun frequencyLoad(): Double {
        var sumCur = 0.0
        var sumMax = 0.0
        val cores = Runtime.getRuntime().availableProcessors()
        for (i in 0 until cores) {
            val cur = readLong("/sys/devices/system/cpu/cpu$i/cpufreq/scaling_cur_freq")
            val max = readLong("/sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq")
            val min = readLong("/sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_min_freq")
            if (cur < 0 || max <= 0) continue
            val floor = if (min in 0 until max) min else 0L
            sumCur += (cur - floor).coerceAtLeast(0L).toDouble()
            sumMax += (max - floor).toDouble()
        }
        return if (sumMax > 0) (sumCur * 100.0 / sumMax).coerceIn(0.0, 100.0) else -1.0
    }

    private fun readLong(path: String): Long = try {
        File(path).readText().trim().toLong()
    } catch (_: Exception) {
        -1L
    }

    private fun memory(): Map<String, Any?> {
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo()
        manager.getMemoryInfo(info)
        var swapTotal = 0L
        var swapFree = 0L
        var cached = 0L
        try {
            for (line in File("/proc/meminfo").readLines()) {
                val kb = line.substringAfter(':').trim().substringBefore(' ').toLongOrNull() ?: continue
                when {
                    line.startsWith("SwapTotal") -> swapTotal = kb * 1024
                    line.startsWith("SwapFree") -> swapFree = kb * 1024
                    line.startsWith("Cached:") -> cached = kb * 1024
                }
            }
        } catch (_: Exception) {
        }
        return mapOf(
            "total" to info.totalMem,
            "available" to info.availMem,
            "used" to (info.totalMem - info.availMem),
            "low" to info.lowMemory,
            "cached" to cached,
            "swapTotal" to swapTotal,
            "swapUsed" to (swapTotal - swapFree)
        )
    }

    private fun storage(): Map<String, Any?> {
        val internal = StatFs(Environment.getDataDirectory().path)
        return mapOf(
            "total" to internal.totalBytes,
            "free" to internal.availableBytes,
            "used" to (internal.totalBytes - internal.availableBytes)
        )
    }

    private fun battery(): Map<String, Any?> {
        val intent: Intent? = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        if (intent == null) return mapOf("available" to false)
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
        val temp = intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) / 10.0
        val voltage = intent.getIntExtra(BatteryManager.EXTRA_VOLTAGE, 0)
        return mapOf(
            "available" to true,
            "percent" to if (level >= 0 && scale > 0) level * 100 / scale else -1,
            "charging" to (status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL),
            "plugged" to when (plugged) {
                BatteryManager.BATTERY_PLUGGED_AC -> "ac"
                BatteryManager.BATTERY_PLUGGED_USB -> "usb"
                BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
                else -> "none"
            },
            "temperature" to temp,
            "voltage" to voltage
        )
    }

    private fun network(): Map<String, Any?> {
        val now = SystemClock.elapsedRealtime()
        val rx = TrafficStats.getTotalRxBytes()
        val tx = TrafficStats.getTotalTxBytes()
        var rxRate = 0.0
        var txRate = 0.0
        if (lastRx >= 0 && now > lastNetTime && rx != TrafficStats.UNSUPPORTED.toLong()) {
            val seconds = (now - lastNetTime) / 1000.0
            rxRate = ((rx - lastRx) / seconds).coerceAtLeast(0.0)
            txRate = ((tx - lastTx) / seconds).coerceAtLeast(0.0)
        }
        lastRx = rx
        lastTx = tx
        lastNetTime = now
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val active = manager.activeNetwork
        val caps = active?.let { manager.getNetworkCapabilities(it) }
        val type = when {
            caps == null -> "offline"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            else -> "other"
        }
        return mapOf(
            "type" to type,
            "validated" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) ?: false),
            "rxBytes" to rx,
            "txBytes" to tx,
            "rxRate" to rxRate,
            "txRate" to txRate
        )
    }

    fun interfaces(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val all = try {
            NetworkInterface.getNetworkInterfaces()?.toList() ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
        for (nif in all) {
            val addresses = nif.interfaceAddresses.map {
                mapOf(
                    "address" to (it.address.hostAddress ?: "").substringBefore('%'),
                    "prefix" to it.networkPrefixLength.toInt(),
                    "ipv6" to (it.address is java.net.Inet6Address)
                )
            }
            val mac = try {
                nif.hardwareAddress?.joinToString(":") { "%02x".format(it) }
            } catch (_: Exception) {
                null
            }
            out.add(
                mapOf(
                    "name" to nif.name,
                    "up" to nif.isUp,
                    "loopback" to nif.isLoopback,
                    "mtu" to nif.mtu,
                    "mac" to mac,
                    "addresses" to addresses
                )
            )
        }
        return out
    }
}
