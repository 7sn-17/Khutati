package com.khutati.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.content.SharedPreferences
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "khutati/focus_timer"

    override fun getInitialRoute(): String? {
        if (intent?.getStringExtra("route") == "/focus") return "/focus"
        return super.getInitialRoute()
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        persistPendingAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        persistPendingAction(intent)
    }

    private fun persistPendingAction(intent: Intent?) {
        val action = intent?.getStringExtra("focus_action") ?: return
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString("flutter.pending_focus_action", action)
            .apply()
    }

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
                        val taskTitle = call.argument<String>("taskTitle")
                        val hasNextStep = call.argument<Boolean>("hasNextStep") ?: false
                        val intent = Intent(this, FocusTimerService::class.java).apply {
                            action = FocusTimerService.ACTION_START
                            putExtra(FocusTimerService.EXTRA_DURATION, duration.toLong())
                            putExtra(FocusTimerService.EXTRA_TASK, taskId)
                            putExtra(FocusTimerService.EXTRA_STEP, stepId)
                            putExtra(FocusTimerService.EXTRA_PHASE, phase)
                            putExtra(FocusTimerService.EXTRA_TASK_TITLE, taskTitle)
                            putExtra(FocusTimerService.EXTRA_HAS_NEXT_STEP, hasNextStep)
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
                    "openBatterySettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (_: Exception) {
                            try {
                                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (_: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
