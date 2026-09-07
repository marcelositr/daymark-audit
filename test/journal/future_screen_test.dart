import 'package:daymark/features/journal/data/future_log_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:daymark/features/journal/presentation/future_screen.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:daymark/presentation/app_section_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Future loads the next six month buckets and captures a Task', (
    tester,
  ) async {
    final _MemoryFutureJournal dataSource = _MemoryFutureJournal();

    await _pumpFuture(tester, dataSource);

    expect(dataSource.loadedPeriods.take(6), <String>[
      '2026-10-01',
      '2026-11-01',
      '2026-12-01',
      '2027-01-01',
      '2027-02-01',
      '2027-03-01',
    ]);

    await tester.enterText(find.byType(TextField), 'Renew passport');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    final FutureLogEntry entry = dataSource.entriesFor('2026-10-01').single;
    expect(entry.type, JournalEntryType.task);
    expect(entry.taskState, JournalTaskState.open);
    expect(entry.content, 'Renew passport');
    expect(find.text('•'), findsOneWidget);
    expect(find.text('Entry created.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Future refreshes retained snapshots when its section activates',
    (tester) async {
      final _MemoryFutureJournal dataSource = _MemoryFutureJournal();
      final ValueNotifier<int> currentSection = ValueNotifier<int>(
        AppSectionScope.futureSectionIndex,
      );
      addTearDown(currentSection.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            futureJournalDataSourceProvider.overrideWithValue(dataSource),
          ],
          child: AppSectionScope(
            currentIndex: currentSection,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: FutureScreen(initialDate: DateTime(2026, 9, 2)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Scheduled elsewhere'), findsNothing);
      dataSource
          .entriesFor('2026-10-01')
          .add(
            const FutureLogEntry(
              id: 'scheduled-1',
              type: JournalEntryType.task,
              taskState: JournalTaskState.open,
              content: 'Scheduled elsewhere',
              ordinal: 0,
            ),
          );

      currentSection.value = 0;
      await tester.pump();
      expect(find.text('Scheduled elsewhere'), findsNothing);

      currentSection.value = AppSectionScope.futureSectionIndex;
      await tester.pumpAndSettle();

      expect(find.text('Scheduled elsewhere'), findsOneWidget);
      expect(
        dataSource.loadedPeriods.where((period) => period == '2026-10-01'),
        hasLength(2),
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Future captures an Event with Rapid Logging semantics', (
    tester,
  ) async {
    final _MemoryFutureJournal dataSource = _MemoryFutureJournal();

    await _pumpFuture(tester, dataSource);

    await tester.tap(find.byKey(const ValueKey<String>('future-entry-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Event').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Conference');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    final FutureLogEntry entry = dataSource.entriesFor('2026-10-01').single;
    expect(entry.type, JournalEntryType.event);
    expect(entry.taskState, isNull);
    expect(find.text('○'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Future open Task can be completed deliberately', (tester) async {
    final _MemoryFutureJournal dataSource = _MemoryFutureJournal(
      entriesByPeriod: <String, List<FutureLogEntry>>{
        '2026-10-01': <FutureLogEntry>[
          const FutureLogEntry(
            id: 'task-1',
            type: JournalEntryType.task,
            taskState: JournalTaskState.open,
            content: 'Book lodging',
            ordinal: 0,
          ),
        ],
      },
    );

    await _pumpFuture(tester, dataSource);

    await tester.tap(find.text('Book lodging'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();

    expect(
      dataSource.entriesFor('2026-10-01').single.taskState,
      JournalTaskState.completed,
    );
    expect(find.text('×'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Future discarded Task remains visible and struck through', (
    tester,
  ) async {
    final _MemoryFutureJournal dataSource = _MemoryFutureJournal(
      entriesByPeriod: <String, List<FutureLogEntry>>{
        '2026-10-01': <FutureLogEntry>[
          const FutureLogEntry(
            id: 'task-1',
            type: JournalEntryType.task,
            taskState: JournalTaskState.open,
            content: 'Old future task',
            ordinal: 0,
          ),
        ],
      },
    );

    await _pumpFuture(tester, dataSource);

    await tester.tap(find.text('•'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(
      dataSource.entriesFor('2026-10-01').single.taskState,
      JournalTaskState.discarded,
    );
    final Text marker = tester.widget<Text>(find.text('•'));
    final Text content = tester.widget<Text>(find.text('Old future task'));
    expect(marker.style?.decoration, TextDecoration.lineThrough);
    expect(content.style?.decoration, TextDecoration.lineThrough);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Future exposes entry type and Task state to semantics', (
    tester,
  ) async {
    final _MemoryFutureJournal dataSource = _MemoryFutureJournal(
      entriesByPeriod: <String, List<FutureLogEntry>>{
        '2026-10-01': <FutureLogEntry>[
          const FutureLogEntry(
            id: 'task-a11y',
            type: JournalEntryType.task,
            taskState: JournalTaskState.open,
            content: 'Accessible future task',
            ordinal: 0,
          ),
        ],
      },
    );

    await _pumpFuture(tester, dataSource);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Task, Open, Accessible future task',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _pumpFuture(
  WidgetTester tester,
  _MemoryFutureJournal dataSource,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        futureJournalDataSourceProvider.overrideWithValue(dataSource),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: FutureScreen(initialDate: DateTime(2026, 9, 2))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _MemoryFutureJournal implements FutureJournalDataSource {
  _MemoryFutureJournal({Map<String, List<FutureLogEntry>>? entriesByPeriod})
    : _entriesByPeriod = entriesByPeriod ?? <String, List<FutureLogEntry>>{};

  final Map<String, List<FutureLogEntry>> _entriesByPeriod;
  final List<String> loadedPeriods = <String>[];

  List<FutureLogEntry> entriesFor(String periodStart) {
    return _entriesByPeriod.putIfAbsent(periodStart, () => <FutureLogEntry>[]);
  }

  @override
  Future<FutureLogSnapshot> load(String periodStart) async {
    loadedPeriods.add(periodStart);
    return FutureLogSnapshot(
      logId: 'future-$periodStart',
      periodStart: periodStart,
      entries: entriesFor(periodStart),
    );
  }

  @override
  Future<FutureLogSnapshot?> find(String periodStart) async => null;

  @override
  Future<void> capture({
    required String logId,
    required JournalEntryType type,
    required String content,
  }) async {
    final String periodStart = logId.substring('future-'.length);
    final List<FutureLogEntry> entries = entriesFor(periodStart);
    entries.add(
      FutureLogEntry(
        id: 'entry-${entries.length}',
        type: type,
        taskState: type == JournalEntryType.task ? JournalTaskState.open : null,
        content: content,
        ordinal: entries.length,
      ),
    );
  }

  @override
  Future<void> completeTask({required String entryId}) async {
    _transitionTask(entryId, JournalTaskState.completed);
  }

  @override
  Future<void> discardTask({required String entryId}) async {
    _transitionTask(entryId, JournalTaskState.discarded);
  }

  void _transitionTask(String entryId, JournalTaskState destinationState) {
    for (final List<FutureLogEntry> entries in _entriesByPeriod.values) {
      final int index = entries.indexWhere((entry) => entry.id == entryId);
      if (index < 0) {
        continue;
      }

      final FutureLogEntry source = entries[index];
      if (source.type != JournalEntryType.task ||
          source.taskState != JournalTaskState.open) {
        throw StateError('Only open Tasks can transition.');
      }

      entries[index] = FutureLogEntry(
        id: source.id,
        type: source.type,
        taskState: destinationState,
        content: source.content,
        ordinal: source.ordinal,
      );
      return;
    }

    throw StateError('Missing entry.');
  }
}
