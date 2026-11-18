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

  // Read the stored settings before the first frame so there is no flash and
  // so the notification channels are created with the user's real choices.
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  // One owner for the notification plugin. Channels whose toggle is OFF are
  // deleted before the first frame, so an OFF switch is never cosmetic.
  await FocusNotifications.init(
    tasks: prefs.getBool(NotificationPrefsController.tasksKey) ?? true,
    daily: prefs.getBool(NotificationPrefsController.dailyKey) ?? true,
    review: prefs.getBool(NotificationPrefsController.reviewKey) ?? true,
    timer: prefs.getBool(NotificationPrefsController.timerKey) ?? true,
  );

  await SoundEffects.init(
    enabled: prefs.getBool(SoundEffects.storageKey) ?? true,
  );

  // Restore the persisted Supabase session before routing decides between
  // Login and Today. With no credentials (local contributor build) the app
  // still renders; the login button reports that sign-in is not configured.
  try {
    await SupabaseAuth.initialize();
  } catch (error) {
    debugPrint('Supabase initialization failed: $error');
  }

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
}
