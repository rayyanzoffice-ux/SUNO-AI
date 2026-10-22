package com.example.suno_ai

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

// Plays the bundled alarm through the alarm audio stream from the app process,
// so the safety countdown is audible even when the activity is not visible. A
// notification sound depends on the channel and the app's notification
// permission; this does not.
object AlarmPlayer {
    private val VIBRATION_CYCLE = longArrayOf(0, 600, 300, 600)
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var stopTask: Runnable? = null

    // Returns false when the tune could not start, so Dart can fall back to
    // vibrating. durationMs of zero or less loops until stop() is called.
    // Runs on the platform thread, where method-channel calls already arrive.
    fun start(context: Context, durationMs: Long): Boolean {
        stopLocked()
        // The attributes overload prepares the file on the alarm stream; calling
        // setAudioAttributes afterwards would be too late and route it as media.
        val created = try {
            MediaPlayer.create(
                context.applicationContext,
                R.raw.suno_alarm,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
                0
            )
        } catch (_: Exception) {
            null
        } ?: return false
        try {
            created.isLooping = true
            created.start()
        } catch (_: Exception) {
            created.release()
            return false
        }
        player = created
        startVibration(context.applicationContext, durationMs)
        if (durationMs > 0) {
            // Stops on the native side too, so a throttled Dart isolate in the
            // background cannot leave the alarm ringing.
            val task = Runnable { stopLocked() }
            stopTask = task
            handler.postDelayed(task, durationMs)
        }
        return true
    }

    fun stop() {
        handler.post { stopLocked() }
    }

    // The vibration repeats for the whole alarm instead of pulsing once with
    // the notification, and it works without notification permission.
    @Suppress("DEPRECATION")
    private fun startVibration(context: Context, durationMs: Long) {
        val device =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                    ?.defaultVibrator
            } else {
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
        if (device == null || !device.hasVibrator()) return
        // A duration-bounded waveform also ends if the process is killed before
        // stopLocked() runs; no duration means the last-resort alarm loops.
        val infinite = durationMs <= 0
        val pattern = if (infinite) VIBRATION_CYCLE else boundedPattern(durationMs)
        val repeat = if (infinite) 0 else -1
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                device.vibrate(VibrationEffect.createWaveform(pattern, repeat))
            } else {
                device.vibrate(pattern, repeat)
            }
            vibrator = device
        } catch (_: Exception) {
        }
    }

    private fun boundedPattern(durationMs: Long): LongArray {
        val repeats = (durationMs / VIBRATION_CYCLE.sum() + 1).coerceAtMost(1000L).toInt()
        return LongArray(VIBRATION_CYCLE.size * repeats) { VIBRATION_CYCLE[it % VIBRATION_CYCLE.size] }
    }

    private fun stopLocked() {
        stopTask?.let { handler.removeCallbacks(it) }
        stopTask = null
        vibrator?.cancel()
        vibrator = null
        player?.let {
            try {
                if (it.isPlaying) it.stop()
                it.release()
            } catch (_: Exception) {
            }
        }
        player = null
    }
}
