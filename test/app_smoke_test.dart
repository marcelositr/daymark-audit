import 'package:daymark/app/appearance_controller.dart';
import 'package:daymark/app/daymark_app.dart';
import 'package:daymark/core/session/journal_session.dart';
import 'package:daymark/core/session/journal_session_controller.dart';
import 'package:daymark/core/settings/appearance_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts on encrypted journal creation when storage is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appearanceControllerProvider.overrideWithBuild(
            (ref, controller) => AppearancePreference.system,
          ),
          journalSessionControllerProvider.overrideWithBuild(
            (ref, controller) => const JournalNeedsCreation(),
          ),
        ],
        child: const DaymarkApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Create your journal'), findsOneWidget);
    expect(find.text('Master password'), findsOneWidget);
    expect(find.text('Confirm master password'), findsOneWidget);
  });

  testWidgets('journal creation rejects an empty master password in the UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appearanceControllerProvider.overrideWithBuild(
            (ref, controller) => AppearancePreference.system,
          ),
          journalSessionControllerProvider.overrideWithBuild(
            (ref, controller) => const JournalNeedsCreation(),
          ),
        ],
        child: const DaymarkApp(),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();

    expect(find.text('A master password is required.'), findsOneWidget);
  });

  group('locale resolution', () {
    test('uses English when the system locale is unsupported', () {
      expect(
        resolveDaymarkLocale(const <Locale>[Locale('fr', 'FR')]),
        const Locale('en'),
      );
    });

    test('uses Spanish for any Spanish regional locale', () {
      expect(
        resolveDaymarkLocale(const <Locale>[Locale('es', 'MX')]),
        const Locale('es'),
      );
      expect(
        resolveDaymarkLocale(const <Locale>[Locale('es', 'ES')]),
        const Locale('es'),
      );
    });

    test('uses Brazilian Portuguese for an exact pt_BR system locale', () {
      expect(
        resolveDaymarkLocale(const <Locale>[Locale('pt', 'BR')]),
        const Locale('pt', 'BR'),
      );
    });

    test('does not treat other Portuguese locales as pt_BR', () {
      expect(
        resolveDaymarkLocale(const <Locale>[Locale('pt', 'PT')]),
        const Locale('en'),
      );
    });
  });

  group('appearance mapping', () {
    test('maps system preference to ThemeMode.system', () {
      expect(
        themeModeForAppearance(AppearancePreference.system),
        ThemeMode.system,
      );
    });

    test('maps explicit light and dark preferences', () {
      expect(
        themeModeForAppearance(AppearancePreference.light),
        ThemeMode.light,
      );
      expect(themeModeForAppearance(AppearancePreference.dark), ThemeMode.dark);
    });
  });
}
