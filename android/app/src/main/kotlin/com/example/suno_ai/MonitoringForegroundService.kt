package com.example.suno_ai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Minimal foreground service that keeps the process alive with a
 * persistent notification while SUNO's Live Mode monitoring pipeline
 * (microphone capture + on-device inference, driven from Dart) is
 * running. This service does not touch audio itself — it only prevents
 * Android from killing the app process while monitoring is active.
 */
class MonitoringForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "suno_monitoring_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "com.example.suno_ai.action.START_MONITORING"
        const val ACTION_STOP = "com.example.suno_ai.action.STOP_MONITORING"
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            else -> startAsForeground()
        }
        return START_STICKY
    }

    private fun startAsForeground() {
        createNotificationChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SUNO is listening")
            .setContentText("Monitoring for emergency sounds in the background.")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "SUNO Monitoring",
                NotificationManager.IMPORTANCE_LOW,
            )
            channel.description = "Shows when SUNO is actively listening for emergencies."
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
