import 'dart:io';

import 'package:daymark/app/appearance_controller.dart';
import 'package:daymark/app/daymark_app.dart';
import 'package:daymark/core/backup/backup_file_gateway.dart';
import 'package:daymark/core/session/journal_session.dart';
import 'package:daymark/core/session/journal_session_controller.dart';
import 'package:daymark/core/settings/appearance_preferences.dart';
import 'package:daymark/features/journal/presentation/backup_dialog.dart';
import 'package:daymark/features/journal/presentation/backup_file_gateway_provider.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty storage offers encrypted backup restore', (tester) async {
    await _pumpAccessState(
      tester,
      state: const JournalNeedsCreation(),
      gateway: const _FakeBackupFileGateway(),
    );

    expect(find.text('Create your journal'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Restore backup'),
      findsOneWidget,
    );
  });

  testWidgets('locked journal offers encrypted backup restore', (tester) async {
    await _pumpAccessState(
      tester,
      state: const JournalLocked(),
      gateway: const _FakeBackupFileGateway(),
    );

    expect(find.text('Unlock Daymark'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Restore backup'),
      findsOneWidget,
    );
  });

  testWidgets('canceling backup selection keeps the locked journal unchanged', (
    tester,
  ) async {
    await _pumpAccessState(
      tester,
      state: const JournalLocked(),
      gateway: const _FakeBackupFileGateway(),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Restore backup'));
    await tester.pumpAndSettle();

    expect(find.text('Unlock Daymark'), findsOneWidget);
    expect(find.text('Restore encrypted backup'), findsNothing);
  });

  testWidgets('selected backup requires explicit destructive confirmation', (
    tester,
  ) async {
    await _pumpAccessState(
      tester,
      state: const JournalLocked(),
      gateway: _FakeBackupFileGateway(
        pickedBackup: File('/tmp/selected.daymark-backup'),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Restore backup'));
    await tester.pumpAndSettle();

    final Finder restoreDialog = find.byType(AlertDialog);

    expect(find.text('Restore encrypted backup'), findsOneWidget);
    expect(
      find.text(
        'Restoring replaces the current journal only after the backup is fully '
        'validated. Daymark must remain locked during restore.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Enter the master password that belongs to this backup.'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: restoreDialog,
        matching: find.text('Master password'),
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Restore'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Restore encrypted backup'), findsNothing);
    expect(find.text('Unlock Daymark'), findsOneWidget);
  });

  testWidgets('backup dialog rejects an empty master password before I/O', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: <Locale>[Locale('en')],
          home: Scaffold(body: BackupDialog()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();

    expect(find.text('A master password is required.'), findsOneWidget);
  });
}

Future<void> _pumpAccessState(
  WidgetTester tester, {
  required JournalAccessState state,
  required BackupFileGateway gateway,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appearanceControllerProvider.overrideWithBuild(
          (ref, controller) => AppearancePreference.system,
        ),
        journalSessionControllerProvider.overrideWithBuild(
          (ref, controller) => state,
        ),
        backupFileGatewayProvider.overrideWithValue(gateway),
      ],
      child: const DaymarkApp(),
    ),
  );
  await tester.pump();
}

final class _FakeBackupFileGateway implements BackupFileGateway {
  const _FakeBackupFileGateway({this.pickedBackup});

  final File? pickedBackup;

  @override
  Future<File?> pickBackup({required String dialogTitle}) async {
    return pickedBackup;
  }

  @override
  Future<bool> saveBackup({
    required File sourceFile,
    required String suggestedName,
    required String dialogTitle,
  }) async {
    throw StateError('saveBackup is not expected in restore UI tests.');
  }
}
