import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'core/settings/theme_mode_controller.dart';
import 'data/database/app_database.dart';
import 'data/database/database_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Arabic month names are needed before the first frame (Plan and Today both
  // print real dates).
  await initializeDateFormatting('ar');
  // Initialise local notifications so permission requests and the focus service
  // notification channel are available from the first frame.
  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await notifications.initialize(
    const InitializationSettings(android: androidInit),
  );

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
