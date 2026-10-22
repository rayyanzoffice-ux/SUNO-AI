package com.example.suno_ai

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper

// Plays the bundled alarm through the alarm audio stream from the app process,
// so the safety countdown is audible even when the activity is not visible. A
// notification sound depends on the channel and the app's notification
// permission; this does not.
object AlarmPlayer {
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
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

    private fun stopLocked() {
        stopTask?.let { handler.removeCallbacks(it) }
        stopTask = null
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
