package com.khutati.app

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "khutati/focus_timer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val duration = (call.argument<Int>("durationMs")
                            ?: call.argument<Long>("durationMs")?.toInt()
                            ?: 0)
                        val taskId = call.argument<String>("taskId")
                        val stepId = call.argument<String>("stepId")
                        val phase = call.argument<String>("phase") ?: "focus"
                        val breakEnabled = call.argument<Boolean>("breakEnabled") ?: true
                        val breakMinutes = call.argument<Int>("breakMinutes") ?: 5
                        val intent = Intent(this, FocusTimerService::class.java).apply {
                            action = FocusTimerService.ACTION_START
                            putExtra(FocusTimerService.EXTRA_DURATION, duration.toLong())
                            putExtra(FocusTimerService.EXTRA_TASK, taskId)
                            putExtra(FocusTimerService.EXTRA_STEP, stepId)
                            putExtra(FocusTimerService.EXTRA_PHASE, phase)
                            putExtra(FocusTimerService.EXTRA_BREAK_ENABLED, breakEnabled)
                            putExtra(FocusTimerService.EXTRA_BREAK_MINUTES, breakMinutes)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "pause" -> {
                        val intent = Intent(this, FocusTimerService::class.java).apply {
                            action = FocusTimerService.ACTION_PAUSE
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "resume" -> {
                        val duration = (call.argument<Int>("durationMs")
                            ?: call.argument<Long>("durationMs")?.toInt()
                            ?: 0)
                        val intent = Intent(this, FocusTimerService::class.java).apply {
                            action = FocusTimerService.ACTION_RESUME
                            putExtra(FocusTimerService.EXTRA_DURATION, duration.toLong())
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "stop" -> {
                        val intent = Intent(this, FocusTimerService::class.java).apply {
                            action = FocusTimerService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "getRemaining" -> {
                        result.success(FocusTimerService.persistedRemaining(this))
                    }
                    "getState" -> {
                        result.success(FocusTimerService.persistedState(this))
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
