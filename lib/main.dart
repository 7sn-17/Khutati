import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'core/notifications/focus_notifications.dart';
import 'core/settings/theme_mode_controller.dart';
import 'data/database/app_database.dart';
import 'data/database/database_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Arabic month names are needed before the first frame (Plan and Today both
  // print real dates).
  await initializeDateFormatting('ar');
  // One owner for the notification plugin. This creates the completion channel
  // with IMPORTANCE_MAX up front (the first channel definition on Android is
  // permanent), so a session that ends while the app is backgrounded still
  // produces a sound.
  await FocusNotifications.init();

  // Read the stored theme before the first frame so there is no flash.
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
}
