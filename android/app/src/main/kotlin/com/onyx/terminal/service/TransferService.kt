package com.onyx.terminal.service

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.onyx.terminal.util.Logger
import com.onyx.terminal.util.Notif

class TransferService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == Notif.ACTION_CANCEL_TRANSFERS) {
            onCancelAll?.invoke()
            return START_NOT_STICKY
        }
        val active = intent?.getIntExtra(EXTRA_ACTIVE, 1) ?: 1
        val percent = intent?.getIntExtra(EXTRA_PERCENT, 0) ?: 0
        val type = if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0
        try {
            ServiceCompat.startForeground(
                this,
                Notif.ID_TRANSFER,
                NotificationHelper.transferNotification(this, active, percent),
                type
            )
        } catch (error: Exception) {
            Logger.w("transfer-service", "Tidak dapat memulai foreground service", error)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    companion object {
        private const val EXTRA_ACTIVE = "active"
        private const val EXTRA_PERCENT = "percent"

        @Volatile
        var onCancelAll: (() -> Unit)? = null

        fun sync(context: Context, active: Int, percent: Int) {
            val intent = Intent(context, TransferService::class.java)
            if (active > 0) {
                intent.putExtra(EXTRA_ACTIVE, active)
                intent.putExtra(EXTRA_PERCENT, percent)
                try {
                    ContextCompat.startForegroundService(context, intent)
                } catch (error: Exception) {
                    Logger.w("transfer-service", "Layanan transfer tidak dapat dimulai", error)
                }
            } else {
                context.stopService(intent)
            }
        }
    }
}
