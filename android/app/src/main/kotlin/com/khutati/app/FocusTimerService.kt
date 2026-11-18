package com.khutati.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

class FocusTimerService : Service() {

    companion object {
        const val CHANNEL_ID = "khutati_focus_timer"
        const val ALERT_CHANNEL_ID = "khutati_focus_alerts"
        const val NOTIF_ID = 4242
        const val ACTION_START = "com.khutati.app.action.START"
        const val ACTION_STOP = "com.khutati.app.action.STOP"
        const val ACTION_PAUSE = "com.khutati.app.action.PAUSE"
        const val ACTION_RESUME = "com.khutati.app.action.RESUME"
        const val EXTRA_DURATION = "duration_ms"
        const val EXTRA_TASK = "task_id"
        const val EXTRA_STEP = "step_id"
        const val EXTRA_PHASE = "phase"
        const val EXTRA_BREAK_ENABLED = "break_enabled"
        const val EXTRA_BREAK_MINUTES = "break_minutes"
        const val PREFS = "khutati_focus"
        const val KEY_TARGET = "target_end_ms"
        const val KEY_PAUSED = "is_paused"
        const val KEY_PAUSED_REMAINING = "paused_remaining_ms"
        const val KEY_PHASE = "phase"
        const val KEY_TASK = "task_id"
        const val KEY_STEP = "step_id"
        const val KEY_BREAK_ENABLED = "break_enabled"
        const val KEY_BREAK_SECONDS = "break_seconds"

        fun persistedRemaining(context: Context): Long {
            val state = persistedState(context)
            return (state["remainingMs"] as? Long) ?: 0L
        }

        fun persistedState(context: Context): HashMap<String, Any> {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val paused = prefs.getBoolean(KEY_PAUSED, false)
            val target = prefs.getLong(KEY_TARGET, 0L)
            val now = System.currentTimeMillis()
            val remaining = if (paused) {
                prefs.getLong(KEY_PAUSED_REMAINING, 0L)
            } else if (target > now) {
                target - now
            } else {
                0L
            }
            return hashMapOf(
                "remainingMs" to remaining,
                "paused" to paused,
                "phase" to (prefs.getString(KEY_PHASE, "focus") ?: "focus"),
            )
        }

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

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val duration = intent.getLongExtra(EXTRA_DURATION, 0L)
                taskId = intent.getStringExtra(EXTRA_TASK)
                stepId = intent.getStringExtra(EXTRA_STEP)
                phase = intent.getStringExtra(EXTRA_PHASE) ?: "focus"
                breakEnabled = intent.getBooleanExtra(EXTRA_BREAK_ENABLED, true)
                breakSeconds = intent.getIntExtra(EXTRA_BREAK_MINUTES, 5) * 60
                targetEndMillis = System.currentTimeMillis() + duration
                pausedRemainingMillis = 0L
                isPaused = false
                persist()
                startForeground(NOTIF_ID, buildNotification())
                scheduleUpdates()
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
                    updateNotification()
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
                }
            }
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                clearPersisted(this)
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
                breakEnabled = prefs.getBoolean(KEY_BREAK_ENABLED, true)
                breakSeconds = prefs.getInt(KEY_BREAK_SECONDS, 300)
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

    private fun persist() {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong(KEY_TARGET, targetEndMillis)
            .putBoolean(KEY_PAUSED, isPaused)
            .putLong(KEY_PAUSED_REMAINING, pausedRemainingMillis)
            .putString(KEY_PHASE, phase)
            .putString(KEY_TASK, taskId)
            .putString(KEY_STEP, stepId)
            .putBoolean(KEY_BREAK_ENABLED, breakEnabled)
            .putInt(KEY_BREAK_SECONDS, breakSeconds)
            .apply()
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "مؤقت التركيز",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
            nm.createNotificationChannel(
                NotificationChannel(
                    ALERT_CHANNEL_ID,
                    "تنبيهات التركيز",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
    }

    private fun remainingMs(): Long {
        return if (isPaused) {
            pausedRemainingMillis
        } else {
            (targetEndMillis - System.currentTimeMillis()).coerceAtLeast(0L)
        }
    }

    private fun pausePendingIntent(): PendingIntent {
        val intent = Intent(this, FocusTimerService::class.java).apply {
            action = ACTION_PAUSE
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
            action = ACTION_STOP
        }
        return PendingIntent.getService(
            this,
            3,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun buildNotification(): Notification {
        val remaining = remainingMs() / 1000
        val minutes = remaining / 60
        val seconds = remaining % 60
        val text = String.format("%02d:%02d", minutes, seconds)
        val title = if (phase == "break") "استراحة" else "تركيز"
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentPi = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentIntent(contentPi)
            .setOngoing(true)
            .setOnlyAlertOnce(true)

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
        return builder.build()
    }

    private fun updateNotification() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIF_ID, buildNotification())
    }

    private fun notifyAlert(title: String, text: String) {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentIntent(pi)
            .setAutoCancel(true)
            .build()
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), notification)
    }

    private fun scheduleUpdates() {
        executor?.shutdownNow()
        executor = Executors.newSingleThreadScheduledExecutor()
        executor?.scheduleAtFixedRate({
            val nm = getSystemService(NotificationManager::class.java)
            if (remainingMs() <= 0) {
                if (phase == "focus") {
                    notifyAlert("اكتملت جلسة التركيز", "هل تريد بدء الاستراحة؟")
                    if (breakEnabled && breakSeconds > 0) {
                        phase = "break"
                        targetEndMillis = System.currentTimeMillis() + breakSeconds * 1000L
                        isPaused = false
                        pausedRemainingMillis = 0L
                        persist()
                        nm.notify(NOTIF_ID, buildNotification())
                        notifyAlert("بدأت الاستراحة", "وقت استراحة قصير")
                        scheduleUpdates()
                    } else {
                        stopForeground(STOP_FOREGROUND_REMOVE)
                        clearPersisted(this)
                        stopSelf()
                    }
                } else {
                    notifyAlert("انتهت الاستراحة", "استأنف التركيز")
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    clearPersisted(this)
                    stopSelf()
                }
            } else {
                nm.notify(NOTIF_ID, buildNotification())
            }
        }, 0, 1, TimeUnit.SECONDS)
    }
}
