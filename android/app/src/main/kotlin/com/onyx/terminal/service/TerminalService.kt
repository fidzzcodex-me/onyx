package com.onyx.terminal.service

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.onyx.terminal.terminal.PtyManager
import com.onyx.terminal.util.Logger
import com.onyx.terminal.util.Notif

class TerminalService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == Notif.ACTION_STOP_ALL) {
            PtyManager.killAll()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val count = intent?.getIntExtra(EXTRA_COUNT, 1) ?: 1
        val type = if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0
        try {
            ServiceCompat.startForeground(
                this,
                Notif.ID_TERMINAL,
                NotificationHelper.terminalNotification(this, count),
                type
            )
        } catch (error: Exception) {
            Logger.w("terminal-service", "Tidak dapat memulai foreground service", error)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    companion object {
        private const val EXTRA_COUNT = "count"

        fun sync(context: Context, count: Int) {
            val intent = Intent(context, TerminalService::class.java)
            if (count > 0) {
                intent.putExtra(EXTRA_COUNT, count)
                try {
                    ContextCompat.startForegroundService(context, intent)
                } catch (error: Exception) {
                    Logger.w("terminal-service", "Layanan tidak dapat dimulai dari latar belakang", error)
                }
            } else {
                context.stopService(intent)
            }
        }
    }
}
