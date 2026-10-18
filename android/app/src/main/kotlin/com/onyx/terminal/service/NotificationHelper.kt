package com.onyx.terminal.service

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.onyx.terminal.MainActivity
import com.onyx.terminal.R
import com.onyx.terminal.util.Notif

object NotificationHelper {
    fun init(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                Notif.CHANNEL_TERMINAL,
                context.getString(R.string.notif_channel_terminal),
                NotificationManager.IMPORTANCE_LOW
            ).apply { description = context.getString(R.string.notif_channel_terminal_desc) }
        )
        manager.createNotificationChannel(
            NotificationChannel(
                Notif.CHANNEL_TRANSFER,
                context.getString(R.string.notif_channel_transfer),
                NotificationManager.IMPORTANCE_LOW
            ).apply { description = context.getString(R.string.notif_channel_transfer_desc) }
        )
        manager.createNotificationChannel(
            NotificationChannel(
                Notif.CHANNEL_ALERT,
                context.getString(R.string.notif_channel_alert),
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply { description = context.getString(R.string.notif_channel_alert_desc) }
        )
    }

    private fun openApp(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun terminalNotification(context: Context, count: Int): Notification {
        val stop = Intent(context, TerminalService::class.java).setAction(Notif.ACTION_STOP_ALL)
        val stopIntent = PendingIntent.getService(
            context, 1, stop, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(context, Notif.CHANNEL_TERMINAL)
            .setSmallIcon(R.mipmap.ic_launcher_monochrome)
            .setContentTitle(context.getString(R.string.notif_terminal_title))
            .setContentText("$count sesi aktif")
            .setContentIntent(openApp(context))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .addAction(0, context.getString(R.string.notif_terminal_close_all), stopIntent)
            .build()
    }

    fun transferNotification(context: Context, active: Int, percent: Int): Notification {
        val cancel = Intent(context, TransferService::class.java).setAction(Notif.ACTION_CANCEL_TRANSFERS)
        val cancelIntent = PendingIntent.getService(
            context, 2, cancel, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(context, Notif.CHANNEL_TRANSFER)
            .setSmallIcon(R.mipmap.ic_launcher_monochrome)
            .setContentTitle(context.getString(R.string.notif_transfer_title))
            .setContentText("$active file diproses, $percent%")
            .setProgress(100, percent.coerceIn(0, 100), false)
            .setContentIntent(openApp(context))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .addAction(0, "Batalkan", cancelIntent)
            .build()
    }

    fun alert(context: Context, key: Int, title: String, text: String) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val notification = NotificationCompat.Builder(context, Notif.CHANNEL_ALERT)
            .setSmallIcon(R.mipmap.ic_launcher_monochrome)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(openApp(context))
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(Notif.ID_ALERT_BASE + key, notification)
        } catch (_: SecurityException) {
        }
    }
}
