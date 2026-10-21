package com.example.suno_ai

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager

/**
 * Sends a single SMS using the device's default SIM. No internet involved —
 * this rides the cellular voice/SMS radio, independent of mobile data.
 *
 * `sendTextMessage` returning without throwing only means the request reached
 * the telephony stack; it is not proof the carrier accepted it (no balance,
 * no signal and no SIM all fail later). The SMS_SENT broadcast is the first
 * point Android itself reports success, so this waits for it (or a timeout)
 * instead of reporting an optimistic `true`.
 *
 * Permission is checked through PackageManager rather than AndroidX's
 * ContextCompat: this module declares no AndroidX dependency, and the direct
 * check works on every API level this app supports.
 */
object SmsSender {
    /** Android usually reports SMS_SENT in under a second; 6s is generous. */
    private const val CONFIRM_TIMEOUT_MS = 6_000L

    fun hasPermission(context: Context): Boolean =
        context.packageManager.checkPermission(
            Manifest.permission.SEND_SMS,
            context.packageName,
        ) == PackageManager.PERMISSION_GRANTED

    /**
     * [onResult] is called exactly once on the main thread with `true` only
     * when Android reports RESULT_OK for every part of the message.
     */
    fun send(
        context: Context,
        phoneNumber: String,
        message: String,
        onResult: (Boolean) -> Unit,
    ) {
        if (!hasPermission(context) || phoneNumber.isBlank() || message.isBlank()) {
            onResult(false)
            return
        }
        @Suppress("DEPRECATION")
        val manager: SmsManager? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java)
            } else {
                SmsManager.getDefault()
            }
        if (manager == null) {
            onResult(false)
            return
        }
        val parts: ArrayList<String> = try {
            manager.divideMessage(message)
        } catch (_: Exception) {
            onResult(false)
            return
        }
        if (parts.isEmpty()) {
            onResult(false)
            return
        }

        val action = "com.example.suno_ai.SMS_SENT.${System.nanoTime()}"
        val handler = Handler(Looper.getMainLooper())
        var remaining = parts.size
        var failed = false
        var completed = false
        lateinit var receiver: BroadcastReceiver

        fun complete(success: Boolean) {
            if (completed) return
            completed = true
            handler.removeCallbacksAndMessages(null)
            try {
                context.unregisterReceiver(receiver)
            } catch (_: Exception) {
                // Already unregistered or never registered.
            }
            onResult(success)
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(receiverContext: Context?, intent: Intent?) {
                // BroadcastReceiver.getResultCode(), not Intent.getResultCode():
                // SmsManager sets the result on the broadcast, not inside the
                // intent payload.
                if (resultCode != Activity.RESULT_OK) failed = true
                remaining -= 1
                if (failed || remaining <= 0) complete(!failed)
            }
        }

        val filter = IntentFilter(action)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                context.registerReceiver(receiver, filter)
            }
        } catch (_: Exception) {
            onResult(false)
            return
        }

        val sentIntents = ArrayList<PendingIntent>(parts.size)
        for (index in parts.indices) {
            val intent = Intent(action).setPackage(context.packageName)
            sentIntents.add(
                PendingIntent.getBroadcast(
                    context,
                    index,
                    intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
        }
        handler.postDelayed({ complete(false) }, CONFIRM_TIMEOUT_MS)

        try {
            if (parts.size > 1) {
                manager.sendMultipartTextMessage(
                    phoneNumber,
                    null,
                    parts,
                    sentIntents,
                    null,
                )
            } else {
                manager.sendTextMessage(phoneNumber, null, parts[0], sentIntents[0], null)
            }
        } catch (_: Exception) {
            complete(false)
        }
    }
}
