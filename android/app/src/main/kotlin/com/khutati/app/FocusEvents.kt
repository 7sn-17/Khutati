package com.khutati.app

import io.flutter.plugin.common.EventChannel

/**
 * One-way push channel from the native focus layer into the Dart state machine.
 *
 * Notification buttons are handled by [FocusTimerService] / [MainActivity]
 * exactly like any other Android app, even while the Flutter UI is visible.
 * Before this channel existed the only bridge was `pending_focus_action` in
 * SharedPreferences, which Dart reads on `resumed` — so tapping "إنهاء" in the
 * shade while the app was already open left the in-app timer counting down.
 *
 * The service and the activity share one process, so a single static sink is
 * enough. [emit] returns `false` when no Flutter engine is attached (cold start
 * / process death); in that case the caller falls back to the persisted action.
 */
object FocusEvents {
    private var sink: EventChannel.EventSink? = null

    @Synchronized
    fun attach(events: EventChannel.EventSink?) {
        sink = events
    }

    @Synchronized
    fun detach() {
        sink = null
    }

    /** Returns `true` when a live Flutter engine accepted the event. */
    @Synchronized
    fun emit(event: String, payload: Map<String, Any?> = emptyMap()): Boolean {
        val target = sink ?: return false
        val data = HashMap<String, Any?>(payload)
        data["event"] = event
        return try {
            target.success(data)
            true
        } catch (_: Exception) {
            // The engine went away between the null check and the call.
            sink = null
            false
        }
    }
}
