import 'package:flutter/services.dart' show rootBundle;

import '../data/database/app_database.dart';
import '../data/database/database_provider.dart';
import '../data/import/plan_importer.dart';

/// The bundled dataset is the only source of plan content (PRD section 3.1).
const String kPlanAsset = 'khutati_plan_data.json';

/// Opens the database and guarantees the 68-day template is present.
///
/// Runs before the first frame: the plan is bundled with the APK, so onboarding
/// can land on Today immediately with no download and no loading screen.
Future<AppDatabase> bootstrapDatabase() async {
  final AppDatabase database = openAppDatabase();
  try {
    final String json = await rootBundle.loadString(kPlanAsset);
    await PlanImporter(database).ensureImported(json);
    return database;
  } catch (_) {
    await database.close();
    rethrow;
  }
}
