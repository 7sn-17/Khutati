package com.khutati.app

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import androidx.core.app.NotificationCompat
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * Foreground countdown for a focus session.
 *
 * The service owns two things the Dart isolate cannot guarantee once Android
 * freezes it: the ongoing notification, and an exact `AlarmManager` wake-up at
 * `targetEndMillis` that posts the completion alert with sound. Dart mirrors
 * this state and reconciles against `targetEndMs` on resume.
 */
class FocusTimerService : Service() {

    companion object {
        const val CHANNEL_ID = "khutati_focus_timer"
        const val ALERT_CHANNEL_ID = "khutati_focus_alerts_v2"
        const val NOTIF_ID = 4242
        const val ALERT_ID = 4243
        const val ACTION_START = "com.khutati.app.action.START"
        const val ACTION_STOP = "com.khutati.app.action.STOP"
        const val ACTION_END = "com.khutati.app.action.END"
        const val ACTION_PAUSE = "com.khutati.app.action.PAUSE"
        const val ACTION_RESUME = "com.khutati.app.action.RESUME"
        const val ACTION_ALARM_EXPIRE = "com.khutati.app.action.ALARM_EXPIRE"
        const val EXTRA_DURATION = "duration_ms"
        const val EXTRA_TASK = "task_id"
        const val EXTRA_STEP = "step_id"
        const val EXTRA_PHASE = "phase"
        const val EXTRA_BREAK_ENABLED = "break_enabled"
        const val EXTRA_BREAK_MINUTES = "break_minutes"
        const val EXTRA_TASK_TITLE = "task_title"
        const val EXTRA_HAS_NEXT_STEP = "has_next_step"
        const val EXTRA_NOTIFY = "notifications_enabled"

        /**
         * Marks an intent as coming from a notification action. Dart-initiated
         * `pause`/`resume` calls start this service too, and echoing those back
         * as events would fight the Dart state machine.
         */
        const val EXTRA_FROM_NOTIFICATION = "from_notification"
        const val PREFS = "khutati_focus"
        const val KEY_TARGET = "target_end_ms"
        const val KEY_PAUSED = "is_paused"
        const val KEY_PAUSED_REMAINING = "paused_remaining_ms"
        const val KEY_PHASE = "phase"
        const val KEY_TASK = "task_id"
        const val KEY_STEP = "step_id"
        const val KEY_BREAK_ENABLED = "break_enabled"
        const val KEY_BREAK_SECONDS = "break_seconds"
        const val KEY_TASK_TITLE = "task_title"
        const val KEY_HAS_NEXT_STEP = "has_next_step"
        const val KEY_NOTIFY = "notifications_enabled"
        const val KEY_PLANNED = "planned_seconds"
        const val ALARM_REQUEST_CODE = 7301

        /**
         * Applies the "تنبيهات الجلسات" toggle to an alarm that is already
         * armed. Deleting the Flutter notification channel is not enough once
         * a session has started: this exact alarm belongs to the native
         * service, so it must be cancelled (or re-armed) here as well.
         */
        fun setNotifications(context: Context, enabled: Boolean) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            prefs.edit().putBoolean(KEY_NOTIFY, enabled).apply()

            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            if (!enabled) manager?.cancel(ALERT_ID)

            val alarmManager =
                context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val phase = prefs.getString(KEY_PHASE, "focus") ?: "focus"
            val operation = PendingIntent.getBroadcast(
                context,
                ALARM_REQUEST_CODE,
                Intent(context, FocusAlarmReceiver::class.java).apply {
                    action = FocusAlarmReceiver.ACTION_ALARM
                    putExtra(EXTRA_PHASE, phase)
                    putExtra(EXTRA_NOTIFY, enabled)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val paused = prefs.getBoolean(KEY_PAUSED, false)
            val target = prefs.getLong(KEY_TARGET, 0L)
            if (!enabled || paused || target <= System.currentTimeMillis()) {
                alarmManager.cancel(operation)
                return
            }

            try {
                val exactAllowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                    alarmManager.canScheduleExactAlarms()
                if (exactAllowed) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        target,
                        operation,
                    )
                } else {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        target,
                        operation,
                    )
                }
            } catch (_: SecurityException) {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    target,
                    operation,
                )
            }
        }

        /** The notification the user sees while a session runs. */
        fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(NotificationManager::class.java) ?: return
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "مؤقت التركيز",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "العدّاد الظاهر أثناء جلسة التركيز"
                    setShowBadge(false)
                },
            )
            // v2: HIGH is what makes the alert a heads-up with sound. A channel
            // definition is permanent, so the id changes whenever the required
            // importance changes.
            nm.createNotificationChannel(
                NotificationChannel(
                    ALERT_CHANNEL_ID,
                    "تنبيهات التركيز",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "صوت واهتزاز عند انتهاء جلسة التركيز أو الاستراحة"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 250, 180, 250)
                    enableLights(true)
                    setShowBadge(true)
                    setSound(
                        Settings.System.DEFAULT_NOTIFICATION_URI,
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                },
            )
        }

        /**
         * Absolute deadline + pause state, read straight from native prefs.
         * `targetEndMs` is what Dart must trust: `remainingMs` alone is what
         * produced the ghost timer.
         */
        fun persistedState(context: Context): HashMap<String, Any> {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val paused = prefs.getBoolean(KEY_PAUSED, false)
            val target = prefs.getLong(KEY_TARGET, 0L)
            val now = System.currentTimeMillis()
            val remaining = when {
                paused -> prefs.getLong(KEY_PAUSED_REMAINING, 0L)
                target > now -> target - now
                else -> 0L
            }
            return hashMapOf(
                "remainingMs" to remaining,
                "paused" to paused,
                "phase" to (prefs.getString(KEY_PHASE, "focus") ?: "focus"),
                "targetEndMs" to target,
                "plannedSeconds" to prefs.getInt(KEY_PLANNED, 0),
                "running" to (target > 0 && !paused),
            )
        }

        fun persistedRemaining(context: Context): Long =
            (persistedState(context)["remainingMs"] as? Long) ?: 0L

        fun clearPersisted(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
        }
    }

    private var executor: ScheduledExecutorService? = null
    private var targetEndMillis: Long = 0L
    private var pausedRemainingMillis: Long = 0L
    private var isPaused: Boolean = false
    private var phase: String = "focus"
    private var taskId: String? = null
    private var stepId: String? = null
    private var breakEnabled: Boolean = true
    private var breakSeconds: Int = 300
    private var taskTitle: String? = null
    private var hasNextStep: Boolean = false
    private var notificationsEnabled: Boolean = true
    private var plannedSeconds: Int = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val duration = intent.getLongExtra(EXTRA_DURATION, 0L)
                taskId = intent.getStringExtra(EXTRA_TASK)
                stepId = intent.getStringExtra(EXTRA_STEP)
                phase = intent.getStringExtra(EXTRA_PHASE) ?: "focus"
                taskTitle = intent.getStringExtra(EXTRA_TASK_TITLE)
                hasNextStep = intent.getBooleanExtra(EXTRA_HAS_NEXT_STEP, false)
                breakEnabled = intent.getBooleanExtra(EXTRA_BREAK_ENABLED, true)
                breakSeconds = intent.getIntExtra(EXTRA_BREAK_MINUTES, 5) * 60
                notificationsEnabled = intent.getBooleanExtra(EXTRA_NOTIFY, true)
                plannedSeconds = (duration / 1000L).toInt()
                targetEndMillis = System.currentTimeMillis() + duration
                pausedRemainingMillis = 0L
                isPaused = false
                persist()
                startForeground(NOTIF_ID, buildNotification())
                scheduleUpdates()
                scheduleAlarm()
            }
            ACTION_PAUSE -> {
                if (!isPaused && targetEndMillis > 0) {
                    pausedRemainingMillis =
                        (targetEndMillis - System.currentTimeMillis()).coerceAtLeast(0L)
                    isPaused = true
                    targetEndMillis = 0L
                    persist()
                    executor?.shutdownNow()
                    executor = null
                    cancelAlarm()
                    updateNotification()
                }
                if (intent.getBooleanExtra(EXTRA_FROM_NOTIFICATION, false)) {
                    // Push the pause into the live Flutter isolate now; the
                    // persisted native state alone is only read on resume.
                    FocusEvents.emit(
                        "pause",
                        mapOf("remainingMs" to pausedRemainingMillis),
                    )
                }
            }
            ACTION_RESUME -> {
                val duration = intent.getLongExtra(EXTRA_DURATION, 0L)
                if (isPaused) {
                    val remaining = if (duration > 0) duration else pausedRemainingMillis
                    targetEndMillis = System.currentTimeMillis() + remaining
                    pausedRemainingMillis = 0L
                    isPaused = false
                    persist()
                    startForeground(NOTIF_ID, buildNotification())
                    scheduleUpdates()
                    scheduleAlarm()
                    if (intent.getBooleanExtra(EXTRA_FROM_NOTIFICATION, false)) {
                        FocusEvents.emit(
                            "resume",
                            mapOf("remainingMs" to remaining),
                        )
                    }
                }
            }
            // The notification's "إنهاء" button. It both pushes the action to a
            // live engine and persists it for a killed process, and it is the
            // only place that produces an "end" action for Dart.
            ACTION_END -> {
                // Deliver the end to a live engine immediately. The persisted
                // copy is always written as well: Dart removes it as soon as it
                // applies the live event, so it is only ever consumed when the
                // process was killed and the event never arrived.
                FocusEvents.emit("end", mapOf("phase" to phase))
                queuePendingAction("end")
                stopForeground(STOP_FOREGROUND_REMOVE)
                cancelAlarm()
                clearPersisted(this)
                stopSelf()
            }
            // Dart-driven stop (session finished, skipped, or reset). It must
            // NOT queue anything: a natural completion used to write "end" into
            // the pending-action slot, and the next launch consumed it and
            // ended the following session.
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                cancelAlarm()
                clearPersisted(this)
                stopSelf()
            }
            ACTION_ALARM_EXPIRE -> {
                // Woken by the exact alarm (or by the receiver). Advance the
                // native phase if the deadline really passed.
                if (remainingMs() <= 0) {
                    handleExpiry()
                } else {
                    scheduleAlarm()
                }
            }
            else -> {
                // Recovery after process death.
                val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                val paused = prefs.getBoolean(KEY_PAUSED, false)
                val target = prefs.getLong(KEY_TARGET, 0L)
                val now = System.currentTimeMillis()
                phase = prefs.getString(KEY_PHASE, "focus") ?: "focus"
                taskId = prefs.getString(KEY_TASK, null)
                stepId = prefs.getString(KEY_STEP, null)
                taskTitle = prefs.getString(KEY_TASK_TITLE, null)
                hasNextStep = prefs.getBoolean(KEY_HAS_NEXT_STEP, false)
                breakEnabled = prefs.getBoolean(KEY_BREAK_ENABLED, true)
                breakSeconds = prefs.getInt(KEY_BREAK_SECONDS, 300)
                notificationsEnabled = prefs.getBoolean(KEY_NOTIFY, true)
                plannedSeconds = prefs.getInt(KEY_PLANNED, 0)
                if (paused) {
                    val remaining = prefs.getLong(KEY_PAUSED_REMAINING, 0L)
                    if (remaining > 0) {
                        isPaused = true
                        pausedRemainingMillis = remaining
                        startForeground(NOTIF_ID, buildNotification())
                    } else {
                        stopSelf()
                    }
                } else if (target > now) {
                    targetEndMillis = target
                    isPaused = false
                    startForeground(NOTIF_ID, buildNotification())
                    scheduleUpdates()
                    scheduleAlarm()
                } else {
                    stopSelf()
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        executor?.shutdownNow()
        executor = null
        super.onDestroy()
    }

    private fun queuePendingAction(action: String) {
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString("flutter.pending_focus_action", action)
            .apply()
    }

    private fun persist() {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong(KEY_TARGET, targetEndMillis)
            .putBoolean(KEY_PAUSED, isPaused)
            .putLong(KEY_PAUSED_REMAINING, pausedRemainingMillis)
            .putString(KEY_PHASE, phase)
            .putString(KEY_TASK, taskId)
            .putString(KEY_STEP, stepId)
            .putString(KEY_TASK_TITLE, taskTitle)
            .putBoolean(KEY_HAS_NEXT_STEP, hasNextStep)
            .putBoolean(KEY_BREAK_ENABLED, breakEnabled)
            .putInt(KEY_BREAK_SECONDS, breakSeconds)
            .putBoolean(KEY_NOTIFY, notificationsEnabled)
            .putInt(KEY_PLANNED, plannedSeconds)
            .apply()
    }

    private fun remainingMs(): Long = if (isPaused) {
        pausedRemainingMillis
    } else {
        (targetEndMillis - System.currentTimeMillis()).coerceAtLeast(0L)
    }

    private fun pausePendingIntent(): PendingIntent {
        val intent = Intent(this, FocusTimerService::class.java).apply {
            action = ACTION_PAUSE
            putExtra(EXTRA_FROM_NOTIFICATION, true)
        }
        return PendingIntent.getService(
            this,
            1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun resumePendingIntent(): PendingIntent {
        val intent = Intent(this, FocusTimerService::class.java).apply {
            action = ACTION_RESUME
            putExtra(EXTRA_DURATION, pausedRemainingMillis)
            putExtra(EXTRA_FROM_NOTIFICATION, true)
        }
        return PendingIntent.getService(
            this,
            2,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun endPendingIntent(): PendingIntent {
        val intent = Intent(this, FocusTimerService::class.java).apply {
            action = ACTION_END
            putExtra(EXTRA_FROM_NOTIFICATION, true)
        }
        return PendingIntent.getService(
            this,
            3,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * Opens the app on the focus screen and carries NO action. Tapping the body
     * of the notification must never mutate the session.
     */
    private fun deepLinkIntent(action: String? = null): Intent {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
        intent.putExtra("route", "/focus")
        if (action != null) intent.putExtra("focus_action", action)
        return intent
    }

    private fun buildNotification(): Notification {
        val remaining = remainingMs() / 1000
        val minutes = remaining / 60
        val seconds = remaining % 60
        val text = String.format(Locale.US, "%02d:%02d", minutes, seconds)
        val title = taskTitle ?: if (phase == "break") "استراحة" else "تركيز"
        val contentPi = PendingIntent.getActivity(
            this,
            0,
            deepLinkIntent(),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(if (phase == "break") "استراحة • $text" else text)
            .setSmallIcon(R.drawable.ic_focus_monochrome)
            .setContentIntent(contentPi)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)

        if (isPaused) {
            builder.addAction(
                android.R.drawable.ic_media_play,
                "استئناف",
                resumePendingIntent(),
            )
        } else {
            builder.addAction(
                android.R.drawable.ic_media_pause,
                "إيقاف مؤقت",
                pausePendingIntent(),
            )
        }
        builder.addAction(
            android.R.drawable.ic_delete,
            "إنهاء",
            endPendingIntent(),
        )
        val thirdLabel = if (hasNextStep) "تخطي"
        else if (breakEnabled && phase == "focus") "بدء الراحة" else null
        val thirdAction = if (hasNextStep) "skip_step"
        else if (breakEnabled && phase == "focus") "start_break" else null
        if (thirdLabel != null && thirdAction != null) {
            val pi = PendingIntent.getActivity(
                this,
                9,
                deepLinkIntent(thirdAction),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            builder.addAction(0, thirdLabel, pi)
        }
        return builder.build()
    }

    private fun updateNotification() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIF_ID, buildNotification())
    }

    private fun scheduleUpdates() {
        executor?.shutdownNow()
        executor = Executors.newSingleThreadScheduledExecutor()
        executor?.scheduleAtFixedRate({
            if (remainingMs() <= 0) {
                // This ticker only *draws* the countdown. It must never drive
                // the transition: doing so let it run just before the exact
                // alarm and call cancelAlarm() on the way out, which is how a
                // 00:00 alert could disappear entirely. The exact alarm owns
                // the expiry while we are backgrounded, and Dart owns it while
                // the app is visible.
                executor?.shutdownNow()
                executor = null
                if (!isAppForeground()) scheduleAlarm()
            } else {
                try {
                    val nm = getSystemService(NotificationManager::class.java)
                    nm.notify(NOTIF_ID, buildNotification())
                } catch (_: Exception) {
                    // The process may be going away; the exact alarm still fires.
                }
            }
        }, 0, 1, TimeUnit.SECONDS)
    }

    private fun isAppForeground(): Boolean =
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getBoolean("flutter.app_foreground", false)

    /**
     * Called only by `ACTION_ALARM_EXPIRE`, i.e. after [FocusAlarmReceiver] has
     * already posted the audible alert. The display ticker never calls it, and
     * while the app is visible the Dart machine owns the transition and its own
     * alert, so the native side stays out of the way to avoid a double sound.
     */
    @Synchronized
    private fun handleExpiry() {
        if (isAppForeground()) return
        executor?.shutdownNow()
        executor = null
        val nm = getSystemService(NotificationManager::class.java)
        if (phase == "focus") {
            if (breakEnabled && breakSeconds > 0) {
                phase = "break"
                plannedSeconds = breakSeconds
                targetEndMillis = System.currentTimeMillis() + breakSeconds * 1000L
                isPaused = false
                pausedRemainingMillis = 0L
                persist()
                try {
                    nm.notify(NOTIF_ID, buildNotification())
                } catch (_: Exception) {
                }
                scheduleUpdates()
                scheduleAlarm()
            } else {
                stopForeground(STOP_FOREGROUND_REMOVE)
                cancelAlarm()
                clearPersisted(this)
                stopSelf()
            }
        } else {
            stopForeground(STOP_FOREGROUND_REMOVE)
            cancelAlarm()
            clearPersisted(this)
            stopSelf()
        }
    }

    private fun alarmPendingIntent(): PendingIntent {
        // Re-read the toggle so a change made after the session started also
        // applies to the next break alarm armed by handleExpiry().
        val latestNotify = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_NOTIFY, notificationsEnabled)
        val intent = Intent(this, FocusAlarmReceiver::class.java).apply {
            action = FocusAlarmReceiver.ACTION_ALARM
            putExtra(EXTRA_PHASE, phase)
            putExtra(EXTRA_NOTIFY, latestNotify)
        }
        return PendingIntent.getBroadcast(
            this,
            ALARM_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * `ScheduledExecutorService` does not survive Doze. The exact alarm is what
     * makes the completion alert fire even when the app has been frozen for
     * minutes.
     */
    private fun scheduleAlarm() {
        if (targetEndMillis <= 0) return
        val alarmManager = getSystemService(AlarmManager::class.java) ?: return
        val operation = alarmPendingIntent()
        try {
            val exactAllowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                alarmManager.canScheduleExactAlarms()
            if (exactAllowed) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    targetEndMillis,
                    operation,
                )
            } else {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    targetEndMillis,
                    operation,
                )
            }
        } catch (_: SecurityException) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                targetEndMillis,
                operation,
            )
        }
    }

    private fun cancelAlarm() {
        getSystemService(AlarmManager::class.java)?.cancel(alarmPendingIntent())
    }
}
