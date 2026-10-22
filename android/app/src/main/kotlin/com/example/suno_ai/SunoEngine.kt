package com.example.suno_ai

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

object SunoEngine {
    private const val ENGINE_ID = "suno_runtime"
    var engine: FlutterEngine? = null
        private set
    private var channel: MethodChannel? = null
    private var pendingStart: MethodChannel.Result? = null
    private val pendingStops = mutableListOf<MethodChannel.Result>()

    fun get(context: Context): FlutterEngine {
        engine?.let { return it }
        val app = context.applicationContext
        val created = FlutterEngine(app)
        engine = created
        FlutterEngineCache.getInstance().put(ENGINE_ID, created)
        channel = MethodChannel(created.dartExecutor.binaryMessenger, "com.example.suno_ai/monitoring_service").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        if (pendingStart != null) {
                            result.error("START_PENDING", "Monitoring is already starting", null)
                        } else {
                            pendingStart = result
                            try {
                                val intent = Intent(app, MonitoringForegroundService::class.java)
                                    .putExtra("locationEnabled", call.argument<Boolean>("locationEnabled") == true)
                                    .putExtra("microphoneEnabled", call.argument<Boolean>("microphoneEnabled") == true)
                                    .putExtra("status", call.argument<String>("status") ?: "SUNO is listening")
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) app.startForegroundService(intent)
                                else app.startService(intent)
                            } catch (_: Exception) {
                                completeStart(false)
                            }
                        }
                    }
                    "updateStatus" -> {
                        val service = MonitoringForegroundService.running
                        if (service == null) {
                            result.error("SERVICE_STOPPED", "The monitoring service is no longer running", null)
                        } else {
                            service.updateStatus(call.argument<String>("status") ?: "SUNO is listening")
                            result.success(null)
                        }
                    }
                    "stop" -> {
                        completeStart(false)
                        val service = MonitoringForegroundService.running
                        if (service == null) {
                            app.stopService(Intent(app, MonitoringForegroundService::class.java))
                            result.success(null)
                        } else {
                            pendingStops.add(result)
                            service.stopFromApp()
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(created.dartExecutor.binaryMessenger, "com.example.suno_ai/sms").setMethodCallHandler { call, result ->
            when (call.method) {
                "send" -> {
                    val phone = call.argument<String>("phone")
                    val message = call.argument<String>("message")
                    if (phone.isNullOrBlank() || message.isNullOrBlank()) {
                        result.success(false)
                    } else {
                        // Resolves after Android's SMS_SENT broadcast (or timeout),
                        // so Dart never counts a merely queued SMS as delivered.
                        SmsSender.send(app, phone, message) { accepted ->
                            Handler(Looper.getMainLooper()).post {
                                result.success(accepted)
                            }
                        }
                    }
                }
                "hasPermission" -> result.success(SmsSender.hasPermission(app))
                else -> result.notImplemented()
            }
        }
        MethodChannel(created.dartExecutor.binaryMessenger, "com.example.suno_ai/alarm").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val durationMs = call.argument<Number>("durationMs")?.toLong() ?: 0L
                    result.success(AlarmPlayer.start(app, durationMs))
                }
                "stop" -> {
                    AlarmPlayer.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        created.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        return created
    }

    fun completeStart(success: Boolean) {
        val result = pendingStart
        pendingStart = null
        if (success) result?.success(null)
        else result?.error("SERVICE_START_FAILED", "Android could not start microphone monitoring. Open SUNO and check permissions.", null)
    }

    fun completeStop() {
        val results = pendingStops.toList()
        pendingStops.clear()
        results.forEach { it.success(null) }
    }

    fun requestStop() {
        channel?.invokeMethod("stopRequested", null)
    }

    fun notifyServiceStopped() {
        completeStart(false)
        channel?.invokeMethod("serviceStopped", null)
    }
}
