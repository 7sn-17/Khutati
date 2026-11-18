package com.khutati.app

import android.Manifest
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * Fires at the exact end of a focus or break phase.
 *
 * This exists because a Dart `Timer` does not run while Android has frozen the
 * app; the previous implementation relied on it alone, which is why the
 * completion sound never fired with the screen off.
 *
 * When the app is in the foreground the Dart state machine posts the alert and
 * owns the transition, so the receiver stays silent to avoid a double alert.
 */
class FocusAlarmReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_ALARM = "com.khutati.app.action.ALARM"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ACTION_ALARM) return

        val phase = intent.getStringExtra(FocusTimerService.EXTRA_PHASE) ?: "focus"
        val wanted = intent.getBooleanExtra(FocusTimerService.EXTRA_NOTIFY, true)
        if (!wanted) return
        if (isAppForeground(context)) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        // Let the service advance the native phase (and arm the break alarm).
        // If it cannot be started, the app reconciles against targetEndMs on
        // the next resume, so the notification below is still correct.
        try {
            val service = Intent(context, FocusTimerService::class.java).apply {
                action = FocusTimerService.ACTION_ALARM_EXPIRE
            }
            context.startService(service)
        } catch (_: Exception) {
        }

        FocusTimerService.ensureChannels(context)

        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: return
        launch.flags = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
        launch.putExtra("route", "/focus")
        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(
            context,
            FocusTimerService.ALERT_CHANNEL_ID,
        )
            .setContentTitle(
                if (phase == "break") "انتهت الاستراحة" else "انتهى وقت التركيز",
            )
            .setContentText(
                if (phase == "break") "وقت العودة للدراسة." else "أحسنت! أكملت جلسة التركيز.",
            )
            .setSmallIcon(R.drawable.ic_focus_monochrome)
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setVibrate(longArrayOf(0, 250, 180, 250))
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setTicker("مؤقت التركيز")
            .build()

        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        manager?.notify(FocusTimerService.ALERT_ID, notification)
    }

    private fun isAppForeground(context: Context): Boolean {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
        return prefs.getBoolean("flutter.app_foreground", false)
    }
}
