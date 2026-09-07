import 'package:daymark/features/journal/data/collection_repository.dart';
import 'package:daymark/features/journal/data/daily_log_repository.dart';
import 'package:daymark/features/journal/data/future_log_repository.dart';
import 'package:daymark/features/journal/data/monthly_log_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:daymark/features/journal/presentation/entry_collection_reference_dialog.dart';
import 'package:daymark/features/journal/presentation/future_screen.dart';
import 'package:daymark/features/journal/presentation/monthly_screen.dart';
import 'package:daymark/features/journal/presentation/today_screen.dart';
import 'package:daymark/features/journal/presentation/tracker_data_source.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tracker_test_data_source.dart';

void main() {
  testWidgets('Today Note can be referenced without changing its source', (
    tester,
  ) async {
    final _ReferenceDataSource references = _ReferenceDataSource();
    final _TodayJournal today = _TodayJournal();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayJournalDataSourceProvider.overrideWithValue(today),
          trackerDataSourceProvider.overrideWithValue(
            const EmptyTrackerDataSource(),
          ),
          entryCollectionReferenceDataSourceProvider.overrideWithValue(
            references,
          ),
        ],
        child: _app(const TodayScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('–'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reference'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project'));
    await tester.pumpAndSettle();

    expect(references.entryId, 'today-note');
    expect(references.collectionId, 'project');
    expect(today.entry.type, JournalEntryType.note);
    expect(today.entry.taskState, isNull);
    expect(find.text('–'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Monthly Calendar Event can be referenced without moving it', (
    tester,
  ) async {
    final _ReferenceDataSource references = _ReferenceDataSource();
    final _MonthlyJournal monthly = _MonthlyJournal();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monthlyJournalDataSourceProvider.overrideWithValue(monthly),
          trackerDataSourceProvider.overrideWithValue(
            const EmptyTrackerDataSource(),
          ),
          entryCollectionReferenceDataSourceProvider.overrideWithValue(
            references,
          ),
        ],
        child: _app(MonthlyScreen(initialMonth: DateTime(2026, 9, 3))),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Monthly event'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reference'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project'));
    await tester.pumpAndSettle();

    expect(references.entryId, 'monthly-event');
    expect(monthly.entry.calendarDate, '2026-09-03');
    expect(monthly.entry.taskState, isNull);
    expect(find.text('Monthly event'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'Future Event can be referenced without changing Future ownership',
    (tester) async {
      final _ReferenceDataSource references = _ReferenceDataSource();
      final _FutureJournal future = _FutureJournal();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            futureJournalDataSourceProvider.overrideWithValue(future),
            entryCollectionReferenceDataSourceProvider.overrideWithValue(
              references,
            ),
          ],
          child: _app(FutureScreen(initialDate: DateTime(2026, 9, 3))),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('○'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reference'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Project'));
      await tester.pumpAndSettle();

      expect(references.entryId, 'future-event');
      expect(future.entry.type, JournalEntryType.event);
      expect(future.entry.taskState, isNull);
      expect(find.text('Future event'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    },
  );
}

MaterialApp _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

final class _ReferenceDataSource implements EntryCollectionReferenceDataSource {
  String? entryId;
  String? collectionId;

  @override
  Future<List<CollectionSummary>> listCollections() async => const [
    CollectionSummary(id: 'project', title: 'Project'),
  ];

  @override
  Future<void> referenceEntry({
    required String entryId,
    required String collectionId,
  }) async {
    this.entryId = entryId;
    this.collectionId = collectionId;
  }
}

final class _TodayJournal implements TodayJournalDataSource {
  final DailyLogEntry entry = const DailyLogEntry(
    id: 'today-note',
    type: JournalEntryType.note,
    taskState: null,
    content: 'Linked observation',
    ordinal: 0,
  );

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
  final MonthlyLogEntry entry = const MonthlyLogEntry(
    id: 'monthly-event',
    type: JournalEntryType.event,
    taskState: null,
    content: 'Monthly event',
    ordinal: 0,
    section: JournalMonthlySection.calendar,
    calendarDate: '2026-09-03',
  );

  @override
  Future<MonthlyLogSnapshot> load(String periodStart) async =>
      MonthlyLogSnapshot(
        logId: 'monthly',
        periodStart: periodStart,
        calendarEntries: [entry],
        taskEntries: const [],
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

final class _FutureJournal implements FutureJournalDataSource {
  final FutureLogEntry entry = const FutureLogEntry(
    id: 'future-event',
    type: JournalEntryType.event,
    taskState: null,
    content: 'Future event',
    ordinal: 0,
  );

  @override
  Future<FutureLogSnapshot> load(String periodStart) async => FutureLogSnapshot(
    logId: 'future-$periodStart',
    periodStart: periodStart,
    entries: periodStart == '2026-10-01' ? [entry] : const [],
  );

  @override
  Future<FutureLogSnapshot?> find(String periodStart) async => null;

  @override
  Future<void> capture({
    required String logId,
    required JournalEntryType type,
    required String content,
  }) async {}

  @override
  Future<void> completeTask({required String entryId}) async {}

  @override
  Future<void> discardTask({required String entryId}) async {}
}
