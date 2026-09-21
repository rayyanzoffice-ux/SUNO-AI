package com.example.suno_ai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import io.flutter.embedding.engine.FlutterEngine

class MonitoringForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "suno_monitoring_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_STOP = "com.example.suno_ai.action.STOP_MONITORING"
        var running: MonitoringForegroundService? = null
            private set
    }

    private var runtimeEngine: FlutterEngine? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var status = "Starting monitoring"
    private var expectedStop = false
    private var microphoneEnabled = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            SunoEngine.requestStop()
            return START_NOT_STICKY
        }
        runtimeEngine = SunoEngine.engine
        if (runtimeEngine == null || intent == null) {
            SunoEngine.completeStart(false)
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            createNotificationChannel()
            status = intent.getStringExtra("status") ?: "SUNO is listening"
            microphoneEnabled = intent.getBooleanExtra("microphoneEnabled", false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                var types = 0
                if (microphoneEnabled) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) types = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                    if (intent.getBooleanExtra("locationEnabled", false)) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    types = ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE
                }
                startForeground(NOTIFICATION_ID, buildNotification(), types)
            } else {
                startForeground(NOTIFICATION_ID, buildNotification())
            }
            running = this
            if (wakeLock == null) {
                wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "SUNO:monitoring").apply {
                        setReferenceCounted(false)
                        acquire()
                    }
            }
            SunoEngine.completeStart(true)
        } catch (_: Exception) {
            SunoEngine.completeStart(false)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    fun stopFromApp() {
        expectedStop = true
        stopSelf()
    }

    override fun onTimeout(startId: Int) {
        stopSelf()
    }

    fun updateStatus(value: String) {
        status = value
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val launch = PendingIntent.getActivity(this, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this, 1,
            Intent(this, MonitoringForegroundService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL_ID)
            else @Suppress("DEPRECATION") Notification.Builder(this)
        return builder.setContentTitle(status)
            .setContentText(if (microphoneEnabled) "Tap to open SUNO. Stop turns off microphone monitoring." else "Tap to view the pending safety action. Microphone is off.")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(launch).setOngoing(true).setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "SUNO Monitoring", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Shows actual microphone monitoring and pending safety actions."
            channel.setSound(null, null)
            channel.enableVibration(false)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        running = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        runtimeEngine = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        if (!expectedStop) SunoEngine.notifyServiceStopped()
        super.onDestroy()
        SunoEngine.completeStop()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
