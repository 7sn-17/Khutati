package com.khutati.app

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "khutati/focus_timer"
    private val eventsChannelName = "khutati/focus_events"

    override fun getInitialRoute(): String? {
        if (intent?.getStringExtra("route") == "/focus") return "/focus"
        return super.getInitialRoute()
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        persistPendingAction(intent)
    }

    override fun onResume() {
        super.onResume()
        setAppForeground(true)
    }

    override fun onPause() {
        setAppForeground(false)
        super.onPause()
    }

    /**
     * The service and the exact-alarm receiver use this to stay silent while
     * the Dart state machine is alive and doing the alerting itself.
     */
    private fun setAppForeground(value: Boolean) {
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit()
            .putBoolean("flutter.app_foreground", value)
            .apply()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        persistPendingAction(intent)
    }

    /**
     * Notification actions that open the app (skip step, start break). A live
     * engine gets the action immediately through [FocusEvents]; only a cold
     * start has to wait for Dart to read the persisted value.
     */
    private fun persistPendingAction(intent: Intent?) {
        val action = intent?.getStringExtra("focus_action") ?: return
        // Consume the extra so a recreated activity cannot replay it.
        intent.removeExtra("focus_action")
        if (FocusEvents.emit(action)) return
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString("flutter.pending_focus_action", action)
            .apply()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventsChannelName)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(
                        arguments: Any?,
                        events: EventChannel.EventSink?,
                    ) {
                        FocusEvents.attach(events)
                    }

                    override fun onCancel(arguments: Any?) {
                        FocusEvents.detach()
                    }
                },
            )
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
                        val notificationsEnabled =
                            call.argument<Boolean>("notificationsEnabled") ?: true
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
                            putExtra(FocusTimerService.EXTRA_NOTIFY, notificationsEnabled)
                        }
                        forwardToService(intent, foreground = true)
                        result.success(null)
                    }
                    "pause" -> {
                        val intent = Intent(this, FocusTimerService::class.java).apply {
                            action = FocusTimerService.ACTION_PAUSE
                        }
                        forwardToService(intent)
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
                        forwardToService(intent)
                        result.success(null)
                    }
                    "stop" -> {
                        val intent = Intent(this, FocusTimerService::class.java).apply {
                            action = FocusTimerService.ACTION_STOP
                        }
                        forwardToService(intent)
                        result.success(null)
                    }
                    "getRemaining" -> {
                        result.success(FocusTimerService.persistedRemaining(this))
                    }
                    "getState" -> {
                        result.success(FocusTimerService.persistedState(this))
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        val power = getSystemService(Context.POWER_SERVICE) as? PowerManager
                        result.success(
                            power?.isIgnoringBatteryOptimizations(packageName) ?: false,
                        )
                    }
                    "openBatterySettings" -> {
                        result.success(openBatterySettings())
                    }
                    "canScheduleExactAlarms" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                            result.success(true)
                        } else {
                            val alarmManager =
                                getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                            result.success(alarmManager?.canScheduleExactAlarms() ?: true)
                        }
                    }
                    "openExactAlarmSettings" -> {
                        result.success(openExactAlarmSettings())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Hands an intent to [FocusTimerService] without ever crashing the app.
     *
     * A notification action can now be applied while the app sits in the
     * background (the event reaches a live Dart isolate), and Android 8+ blocks
     * background service starts. The native side has already applied the
     * change in that case, and Dart reconciles on the next resume, so failing
     * quietly is the correct behaviour.
     */
    private fun forwardToService(intent: Intent, foreground: Boolean = false) {
        if (foreground && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                startForegroundService(intent)
                return
            } catch (_: Exception) {
                // Fall through to a plain start.
            }
        }
        try {
            startService(intent)
        } catch (_: Exception) {
        }
    }

    /**
     * Opens the battery-optimisation screen for this app. Returns `true` when
     * the app is already unrestricted or a settings screen was launched, and
     * `false` when every option failed — which is what the first-run dialog
     * uses to fall back to a readable message instead of doing nothing.
     */
    private fun openBatterySettings(): Boolean {
        val power = getSystemService(Context.POWER_SERVICE) as? PowerManager
        if (power?.isIgnoringBatteryOptimizations(packageName) == true) return true

        // 1. The direct "allow unrestricted" sheet.
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            return true
        } catch (_: Exception) {
        }

        // 2. The battery-optimisation list (some OEM skins block the sheet).
        try {
            startActivity(
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return true
        } catch (_: Exception) {
        }

        // 3. The app's own settings page, where battery usage is one tap away.
        try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            return true
        } catch (_: Exception) {
        }

        return false
    }

    /**
     * Opens the "Alarms & reminders" settings screen where the user can grant
     * `SCHEDULE_EXACT_ALARM`. Returns `true` when a screen was launched or the
     * permission is already granted.
     */
    private fun openExactAlarmSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        if (alarmManager?.canScheduleExactAlarms() == true) return true

        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            return true
        } catch (_: Exception) {
        }

        try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            return true
        } catch (_: Exception) {
        }

        return false
    }
}
