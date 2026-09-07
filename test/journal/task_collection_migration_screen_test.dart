import 'package:daymark/features/journal/data/collection_repository.dart';
import 'package:daymark/features/journal/data/daily_log_repository.dart';
import 'package:daymark/features/journal/data/monthly_log_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:daymark/features/journal/presentation/monthly_screen.dart';
import 'package:daymark/features/journal/presentation/task_collection_migration_dialog.dart';
import 'package:daymark/features/journal/presentation/today_screen.dart';
import 'package:daymark/features/journal/presentation/tracker_data_source.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tracker_test_data_source.dart';

void main() {
  testWidgets('Today migrates an open Task into a selected Collection', (
    tester,
  ) async {
    final _TodayJournal today = _TodayJournal();
    final _MigrationDataSource migration = _MigrationDataSource(
      onMigrate: (entryId) => today.migrate(entryId),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayJournalDataSourceProvider.overrideWithValue(today),
          trackerDataSourceProvider.overrideWithValue(
            const EmptyTrackerDataSource(),
          ),
          taskCollectionMigrationDataSourceProvider.overrideWithValue(
            migration,
          ),
        ],
        child: _app(const TodayScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('•'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Migrate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Collections'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project'));
    await tester.pumpAndSettle();

    expect(migration.migratedEntryId, 'today-task');
    expect(migration.collectionId, 'project');
    expect(today.entry.taskState, JournalTaskState.migrated);
    expect(find.text('>'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Monthly migrates an open Task into a selected Collection', (
    tester,
  ) async {
    final _MonthlyJournal monthly = _MonthlyJournal();
    final _MigrationDataSource migration = _MigrationDataSource(
      onMigrate: (entryId) => monthly.migrate(entryId),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monthlyJournalDataSourceProvider.overrideWithValue(monthly),
          trackerDataSourceProvider.overrideWithValue(
            const EmptyTrackerDataSource(),
          ),
          taskCollectionMigrationDataSourceProvider.overrideWithValue(
            migration,
          ),
        ],
        child: _app(MonthlyScreen(initialMonth: DateTime(2026, 9, 3))),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Tasks'));
    await tester.pump();

    await tester.tap(find.text('•'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Migrate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Collections'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project'));
    await tester.pumpAndSettle();

    expect(migration.migratedEntryId, 'monthly-task');
    expect(migration.collectionId, 'project');
    expect(monthly.entry.taskState, JournalTaskState.migrated);
    expect(find.text('>'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}

MaterialApp _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

final class _MigrationDataSource implements TaskCollectionMigrationDataSource {
  _MigrationDataSource({required this.onMigrate});

  final void Function(String entryId) onMigrate;
  String? migratedEntryId;
  String? collectionId;

  @override
  Future<List<CollectionSummary>> listCollections() async => const [
    CollectionSummary(id: 'project', title: 'Project'),
  ];

  @override
  Future<void> migrateTask({
    required String entryId,
    required String collectionId,
  }) async {
    migratedEntryId = entryId;
    this.collectionId = collectionId;
    onMigrate(entryId);
  }
}

final class _TodayJournal implements TodayJournalDataSource {
  DailyLogEntry entry = const DailyLogEntry(
    id: 'today-task',
    type: JournalEntryType.task,
    taskState: JournalTaskState.open,
    content: 'Move today',
    ordinal: 0,
  );

  void migrate(String entryId) {
    expect(entryId, entry.id);
    entry = DailyLogEntry(
      id: entry.id,
      type: entry.type,
      taskState: JournalTaskState.migrated,
      content: entry.content,
      ordinal: entry.ordinal,
    );
  }

  @override
  Future<DailyLogSnapshot> load(String methodDate) async => DailyLogSnapshot(
    logId: 'daily',
    methodDate: methodDate,
    entries: [entry],
  );

  @override
  Future<void> capture({
    required String logId,
    required JournalEntryType type,
    required String content,
  }) async {}

  @override
  Future<void> completeTask({required String entryId}) async {}

  @override
  Future<void> scheduleTaskToFuture({
    required String entryId,
    required String periodStart,
  }) async {}

  @override
  Future<void> discardTask({required String entryId}) async {}
}

final class _MonthlyJournal implements MonthlyJournalDataSource {
  MonthlyLogEntry entry = const MonthlyLogEntry(
    id: 'monthly-task',
    type: JournalEntryType.task,
    taskState: JournalTaskState.open,
    content: 'Move monthly',
    ordinal: 0,
    section: JournalMonthlySection.tasks,
    calendarDate: null,
  );

  void migrate(String entryId) {
    expect(entryId, entry.id);
    entry = MonthlyLogEntry(
      id: entry.id,
      type: entry.type,
      taskState: JournalTaskState.migrated,
      content: entry.content,
      ordinal: entry.ordinal,
      section: entry.section,
      calendarDate: entry.calendarDate,
    );
  }

  @override
  Future<MonthlyLogSnapshot> load(String periodStart) async =>
      MonthlyLogSnapshot(
        logId: 'monthly',
        periodStart: periodStart,
        calendarEntries: const [],
        taskEntries: [entry],
      );

  @override
  Future<MonthlyLogSnapshot?> find(String periodStart) => load(periodStart);

  @override
  Future<void> captureCalendarEvent({
    required String logId,
    required String calendarDate,
    required String content,
  }) async {}

  @override
  Future<void> captureTask({
    required String logId,
    required String content,
  }) async {}

  @override
  Future<void> completeTask({required String entryId}) async {}

  @override
  Future<void> scheduleTaskToFuture({
    required String entryId,
    required String periodStart,
  }) async {}

  @override
  Future<void> discardTask({required String entryId}) async {}
}
