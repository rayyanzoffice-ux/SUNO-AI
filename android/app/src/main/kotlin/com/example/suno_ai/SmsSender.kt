package com.example.suno_ai

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager

/**
 * Sends a single SMS using the device's default SIM. No internet involved —
 * this rides the cellular voice/SMS radio, independent of mobile data.
 *
 * Permission is checked through PackageManager rather than AndroidX's
 * ContextCompat: this module declares no AndroidX dependency, and the direct
 * check works on every API level this app supports.
 */
object SmsSender {
    fun hasPermission(context: Context): Boolean =
        context.packageManager.checkPermission(
            Manifest.permission.SEND_SMS,
            context.packageName,
        ) == PackageManager.PERMISSION_GRANTED

    /**
     * Returns true only if the OS accepted the send request. This does not
     * guarantee carrier delivery — SUNO cannot know that without a delivery
     * receipt, which is out of scope for the finale.
     */
    fun send(context: Context, phoneNumber: String, message: String): Boolean {
        if (!hasPermission(context)) return false
        if (phoneNumber.isBlank()) return false
        return try {
            val manager: SmsManager =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    context.getSystemService(SmsManager::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    SmsManager.getDefault()
                }
            val parts = manager.divideMessage(message)
            if (parts.size > 1) {
                manager.sendMultipartTextMessage(phoneNumber, null, parts, null, null)
            } else {
                manager.sendTextMessage(phoneNumber, null, message, null, null)
            }
            true
        } catch (_: Exception) {
            false
        }
    }
}
