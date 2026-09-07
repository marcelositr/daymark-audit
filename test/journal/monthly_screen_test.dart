import 'package:daymark/features/journal/data/monthly_log_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:daymark/features/journal/presentation/monthly_screen.dart';
import 'package:daymark/features/journal/presentation/tracker_data_source.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tracker_test_data_source.dart';

void main() {
  testWidgets('Monthly Calendar captures an Event on the selected day', (
    tester,
  ) async {
    final _MemoryMonthlyJournal dataSource = _MemoryMonthlyJournal();

    await _pumpMonthly(tester, dataSource);

    await tester.enterText(find.byType(TextField), 'Dentist');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await tester.pump();

    expect(dataSource.calendarEntries, hasLength(1));
    expect(dataSource.calendarEntries.single.type, JournalEntryType.event);
    expect(dataSource.calendarEntries.single.calendarDate, '2026-09-15');

    await tester.dragUntilVisible(
      find.text('Dentist'),
      find.byType(ListView),
      const Offset(0, -200),
    );

    expect(find.text('Dentist'), findsOneWidget);
    expect(find.text('Entry created.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Monthly Tasks captures and completes an open Task', (
    tester,
  ) async {
    final _MemoryMonthlyJournal dataSource = _MemoryMonthlyJournal();

    await _pumpMonthly(tester, dataSource);
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Renew documents');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await tester.pump();

    expect(dataSource.taskEntries, hasLength(1));
    expect(dataSource.taskEntries.single.taskState, JournalTaskState.open);
    expect(find.text('•'), findsOneWidget);

    await tester.tap(find.text('Renew documents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete'));
    await tester.pump();
    await tester.pump();

    expect(dataSource.taskEntries.single.taskState, JournalTaskState.completed);
    expect(find.text('×'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Monthly open Task can be scheduled into a Future month', (
    tester,
  ) async {
    final _MemoryMonthlyJournal dataSource = _MemoryMonthlyJournal(
      taskEntries: [
        const MonthlyLogEntry(
          id: 'task-1',
          type: JournalEntryType.task,
          taskState: JournalTaskState.open,
          content: 'Renew in October',
          ordinal: 0,
          section: JournalMonthlySection.tasks,
          calendarDate: null,
        ),
      ],
    );

    await _pumpMonthly(tester, dataSource);
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('•'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();

    expect(find.byType(SimpleDialogOption), findsNWidgets(6));
    await tester.tap(find.byType(SimpleDialogOption).first);
    await tester.pumpAndSettle();

    expect(dataSource.scheduledPeriodStart, '2026-10-01');
    expect(dataSource.taskEntries.single.taskState, JournalTaskState.scheduled);
    expect(find.text('<'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Monthly discarded Task remains visible and struck through', (
    tester,
  ) async {
    final _MemoryMonthlyJournal dataSource = _MemoryMonthlyJournal(
      taskEntries: [
        const MonthlyLogEntry(
          id: 'task-1',
          type: JournalEntryType.task,
          taskState: JournalTaskState.open,
          content: 'Old monthly task',
          ordinal: 0,
          section: JournalMonthlySection.tasks,
          calendarDate: null,
        ),
      ],
    );

    await _pumpMonthly(tester, dataSource);
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('•'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pump();
    await tester.pump();

    expect(dataSource.taskEntries.single.taskState, JournalTaskState.discarded);
    final Text marker = tester.widget<Text>(find.text('•'));
    final Text content = tester.widget<Text>(find.text('Old monthly task'));
    expect(marker.style?.decoration, TextDecoration.lineThrough);
    expect(content.style?.decoration, TextDecoration.lineThrough);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Monthly browses a historical month without creating it', (
    tester,
  ) async {
    final _MemoryMonthlyJournal dataSource = _MemoryMonthlyJournal(
      historicalSnapshots: {
        '2026-08-01': MonthlyLogSnapshot(
          logId: 'monthly-2026-08-01',
          periodStart: '2026-08-01',
          calendarEntries: const [
            MonthlyLogEntry(
              id: 'event-august',
              type: JournalEntryType.event,
              taskState: null,
              content: 'Historic meeting',
              ordinal: 0,
              section: JournalMonthlySection.calendar,
              calendarDate: '2026-08-12',
            ),
          ],
          taskEntries: const [],
        ),
      },
    );

    await _pumpMonthly(tester, dataSource);
    final IconButton currentNext = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(currentNext.onPressed, isNull);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();

    expect(find.text('August 2026'), findsOneWidget);
    expect(find.text('Historical Monthly Logs are read-only.'), findsOneWidget);
    expect(find.text('Historic meeting'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(dataSource.loadPeriods, ['2026-09-01']);
    expect(dataSource.findPeriods, ['2026-08-01']);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('historical Monthly Tasks are read-only and can return current', (
    tester,
  ) async {
    final _MemoryMonthlyJournal dataSource = _MemoryMonthlyJournal(
      historicalSnapshots: {
        '2026-08-01': MonthlyLogSnapshot(
          logId: 'monthly-2026-08-01',
          periodStart: '2026-08-01',
          calendarEntries: const [],
          taskEntries: const [
            MonthlyLogEntry(
              id: 'task-august',
              type: JournalEntryType.task,
              taskState: JournalTaskState.open,
              content: 'Historic task',
              ordinal: 0,
              section: JournalMonthlySection.tasks,
              calendarDate: null,
            ),
          ],
        ),
      },
    );

    await _pumpMonthly(tester, dataSource);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();

    expect(find.text('Historic task'), findsOneWidget);
    expect(find.text('•'), findsOneWidget);
    expect(find.byTooltip('Entry actions'), findsNothing);
    expect(find.byType(TextField), findsNothing);

    final IconButton historicalNext = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(historicalNext.onPressed, isNotNull);

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();

    expect(find.text('September 2026'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(dataSource.loadPeriods, ['2026-09-01', '2026-09-01']);

    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Monthly can open directly on the requested section', (
    tester,
  ) async {
    final _MemoryMonthlyJournal dataSource = _MemoryMonthlyJournal(
      taskEntries: [
        const MonthlyLogEntry(
          id: 'source-task',
          type: JournalEntryType.task,
          taskState: JournalTaskState.open,
          content: 'Direct source task',
          ordinal: 0,
          section: JournalMonthlySection.tasks,
          calendarDate: null,
        ),
      ],
    );

    await _pumpMonthly(
      tester,
      dataSource,
      initialSection: JournalMonthlySection.tasks,
    );

    expect(find.text('Direct source task'), findsOneWidget);
  });
}

Future<void> _pumpMonthly(
  WidgetTester tester,
  _MemoryMonthlyJournal dataSource, {
  JournalMonthlySection? initialSection,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        monthlyJournalDataSourceProvider.overrideWithValue(dataSource),
        trackerDataSourceProvider.overrideWithValue(
          const EmptyTrackerDataSource(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MonthlyScreen(
            initialMonth: DateTime(2026, 9, 15),
            initialSection: initialSection,
            now: () => DateTime(2026, 9, 15),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

final class _MemoryMonthlyJournal implements MonthlyJournalDataSource {
  _MemoryMonthlyJournal({
    List<MonthlyLogEntry>? calendarEntries,
    List<MonthlyLogEntry>? taskEntries,
    Map<String, MonthlyLogSnapshot?> historicalSnapshots = const {},
  }) : calendarEntries = calendarEntries ?? <MonthlyLogEntry>[],
       taskEntries = taskEntries ?? <MonthlyLogEntry>[],
       historicalSnapshots = Map<String, MonthlyLogSnapshot?>.from(
         historicalSnapshots,
       );

  final List<MonthlyLogEntry> calendarEntries;
  final List<MonthlyLogEntry> taskEntries;
  final Map<String, MonthlyLogSnapshot?> historicalSnapshots;
  final List<String> loadPeriods = <String>[];
  final List<String> findPeriods = <String>[];
  String? scheduledPeriodStart;

  @override
  Future<MonthlyLogSnapshot> load(String periodStart) async {
    loadPeriods.add(periodStart);
    return MonthlyLogSnapshot(
      logId: 'monthly-$periodStart',
      periodStart: periodStart,
      calendarEntries: calendarEntries,
      taskEntries: taskEntries,
    );
  }

  @override
  Future<MonthlyLogSnapshot?> find(String periodStart) async {
    findPeriods.add(periodStart);
    return historicalSnapshots[periodStart];
  }

  @override
  Future<void> captureCalendarEvent({
    required String logId,
    required String calendarDate,
    required String content,
  }) async {
    calendarEntries.add(
      MonthlyLogEntry(
        id: 'event-${calendarEntries.length}',
        type: JournalEntryType.event,
        taskState: null,
        content: content,
        ordinal: calendarEntries.length,
        section: JournalMonthlySection.calendar,
        calendarDate: calendarDate,
      ),
    );
  }

  @override
  Future<void> captureTask({
    required String logId,
    required String content,
  }) async {
    taskEntries.add(
      MonthlyLogEntry(
        id: 'task-${taskEntries.length}',
        type: JournalEntryType.task,
        taskState: JournalTaskState.open,
        content: content,
        ordinal: taskEntries.length,
        section: JournalMonthlySection.tasks,
        calendarDate: null,
      ),
    );
  }

  @override
  Future<void> completeTask({required String entryId}) async {
    _transitionTask(entryId, JournalTaskState.completed);
  }

  @override
  Future<void> scheduleTaskToFuture({
    required String entryId,
    required String periodStart,
  }) async {
    scheduledPeriodStart = periodStart;
    _transitionTask(entryId, JournalTaskState.scheduled);
  }

  @override
  Future<void> discardTask({required String entryId}) async {
    _transitionTask(entryId, JournalTaskState.discarded);
  }

  void _transitionTask(String entryId, JournalTaskState destinationState) {
    final int index = taskEntries.indexWhere((entry) => entry.id == entryId);
    if (index < 0) {
      throw StateError('Missing entry.');
    }

    final MonthlyLogEntry source = taskEntries[index];
    if (source.type != JournalEntryType.task ||
        source.taskState != JournalTaskState.open) {
      throw StateError('Only open Tasks can transition.');
    }

    taskEntries[index] = MonthlyLogEntry(
      id: source.id,
      type: source.type,
      taskState: destinationState,
      content: source.content,
      ordinal: source.ordinal,
      section: source.section,
      calendarDate: source.calendarDate,
    );
  }
}
