import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khutati/core/settings/theme_mode_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> containerWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('defaults to following the system', () async {
    final ProviderContainer container = await containerWith(<String, Object>{});
    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('restores the persisted mode on startup', () async {
    final ProviderContainer dark = await containerWith(<String, Object>{'theme_mode': 'dark'});
    expect(dark.read(themeModeProvider), ThemeMode.dark);

    final ProviderContainer light = await containerWith(<String, Object>{'theme_mode': 'light'});
    expect(light.read(themeModeProvider), ThemeMode.light);
  });

  test('unknown stored values fall back to system', () async {
    final ProviderContainer container = await containerWith(<String, Object>{'theme_mode': 'sepia'});
    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('set() persists the choice', () async {
    final ProviderContainer container = await containerWith(<String, Object>{});
    final SharedPreferences prefs = container.read(sharedPreferencesProvider);

    await container.read(themeModeProvider.notifier).set(ThemeMode.dark);

    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(prefs.getString(ThemeModeController.storageKey), 'dark');
  });

  test('cycle() follows the prototype order: system -> dark -> light -> system', () async {
    final ProviderContainer container = await containerWith(<String, Object>{});
    final ThemeModeController controller = container.read(themeModeProvider.notifier);

    expect(container.read(themeModeProvider), ThemeMode.system);
    await controller.cycle();
    expect(container.read(themeModeProvider), ThemeMode.dark);
    await controller.cycle();
    expect(container.read(themeModeProvider), ThemeMode.light);
    await controller.cycle();
    expect(container.read(themeModeProvider), ThemeMode.system);
  });
}
