import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'core/notifications/focus_notifications.dart';
import 'core/settings/notification_prefs.dart';
import 'core/settings/theme_mode_controller.dart';
import 'core/sound/sound_effects.dart';
import 'data/database/app_database.dart';
import 'data/database/database_provider.dart';
import 'features/auth/data/supabase_auth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Arabic month names are needed before the first frame (Plan and Today both
  // print real dates).
  await initializeDateFormatting('ar');

  // Only what the first frame truly needs runs before `runApp`: the persisted
  // settings and the local database. Auth, notification channels and audio are
  // warmed in parallel once the splash is already on screen.
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  // The template import is idempotent: the first launch writes the 68 days,
  // every later launch only compares the dataset hash.
  final AppDatabase database = await bootstrapDatabase();

  runApp(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(database),
      ],
      child: const KhutatiApp(),
    ),
  );

  // The existing 2.5s splash gives these time to finish. A failure in one must
  // not prevent the others from starting, and none may hold the first frame.
  WidgetsBinding.instance.addPostFrameCallback((Duration _) {
    unawaited(_warmUp(prefs));
  });
}

Future<void> _warmUp(SharedPreferences prefs) async {
  await Future.wait<void>(<Future<void>>[
    _guard(
      'notifications',
      FocusNotifications.init(
        tasks: prefs.getBool(NotificationPrefsController.tasksKey) ?? true,
        daily: prefs.getBool(NotificationPrefsController.dailyKey) ?? true,
        review: prefs.getBool(NotificationPrefsController.reviewKey) ?? true,
        timer: prefs.getBool(NotificationPrefsController.timerKey) ?? true,
      ),
    ),
    _guard(
      'sound',
      SoundEffects.init(
        enabled: prefs.getBool(SoundEffects.storageKey) ?? true,
      ),
    ),
    _guard('Supabase', SupabaseAuth.initialize()),
  ]);
}

Future<void> _guard(String label, Future<void> task) async {
  try {
    await task;
  } catch (error) {
    debugPrint('$label initialization failed: $error');
  }
}
