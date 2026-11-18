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
        const val NOTIF_ID = 4242
        const val ACTION_START = "com.khutati.app.action.START"
        const val ACTION_STOP = "com.khutati.app.action.STOP"
        const val EXTRA_DURATION = "duration_ms"
        const val EXTRA_TASK = "task_id"
        const val EXTRA_STEP = "step_id"
        const val PREFS = "khutati_focus"
        const val KEY_TARGET = "target_end_ms"
        const val KEY_TASK = "task_id"
        const val KEY_STEP = "step_id"

        fun persistedRemaining(context: Context): Long {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val target = prefs.getLong(KEY_TARGET, 0L)
            val now = System.currentTimeMillis()
            return if (target > now) target - now else 0L
        }

        fun clearPersisted(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
        }
    }

    private var executor: ScheduledExecutorService? = null
    private var targetEndMillis: Long = 0L
    private var taskId: String? = null
    private var stepId: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val duration = intent.getLongExtra(EXTRA_DURATION, 0L)
                taskId = intent.getStringExtra(EXTRA_TASK)
                stepId = intent.getStringExtra(EXTRA_STEP)
                targetEndMillis = System.currentTimeMillis() + duration
                persist()
                startForeground(NOTIF_ID, buildNotification())
                scheduleUpdates()
            }
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                clearPersisted(this)
            }
            else -> {
                // Recovery after process death.
                val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                val target = prefs.getLong(KEY_TARGET, 0L)
                if (target > System.currentTimeMillis()) {
                    targetEndMillis = target
                    taskId = prefs.getString(KEY_TASK, null)
                    stepId = prefs.getString(KEY_STEP, null)
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
            .putString(KEY_TASK, taskId)
            .putString(KEY_STEP, stepId)
            .apply()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "مؤقت التركيز",
                NotificationManager.IMPORTANCE_LOW,
            )
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun remainingMs(): Long {
        return (targetEndMillis - System.currentTimeMillis()).coerceAtLeast(0L)
    }

    private fun buildNotification(): Notification {
        val remaining = remainingMs() / 1000
        val minutes = remaining / 60
        val seconds = remaining % 60
        val text = String.format("%02d:%02d", minutes, seconds)
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("تركيز")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

    private fun scheduleUpdates() {
        executor?.shutdownNow()
        executor = Executors.newSingleThreadScheduledExecutor()
        executor?.scheduleAtFixedRate({
            val nm = getSystemService(NotificationManager::class.java)
            if (remainingMs() <= 0) {
                nm.notify(NOTIF_ID, buildNotification())
                // auto stop
                stopForeground(STOP_FOREGROUND_REMOVE)
                clearPersisted(this)
                stopSelf()
            } else {
                nm.notify(NOTIF_ID, buildNotification())
            }
        }, 0, 1, TimeUnit.SECONDS)
    }
}