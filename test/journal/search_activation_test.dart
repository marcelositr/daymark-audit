import 'dart:async';

import 'package:daymark/features/journal/data/search_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:daymark/features/journal/presentation/search_screen.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:daymark/presentation/app_section_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Search reruns the last query when its retained section reactivates',
    (tester) async {
      final _MutableSearchJournal dataSource = _MutableSearchJournal();
      final ValueNotifier<int> currentSection = ValueNotifier<int>(
        AppSectionScope.searchSectionIndex,
      );
      addTearDown(currentSection.dispose);

      await _pumpRetainedSearch(tester, dataSource, currentSection);

      await tester.enterText(find.byType(TextField), 'radio');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(dataSource.calls, 1);
      expect(find.text('•'), findsOneWidget);

      currentSection.value = 0;
      await tester.pump();
      dataSource.completed = true;

      currentSection.value = AppSectionScope.searchSectionIndex;
      await tester.pump();
      await tester.pump();

      expect(dataSource.calls, 2);
      expect(find.text('×'), findsOneWidget);
      expect(find.text('•'), findsNothing);
    },
  );

  testWidgets('a new query wins over an in-flight retained refresh', (
    tester,
  ) async {
    final _RaceSearchJournal dataSource = _RaceSearchJournal();
    final ValueNotifier<int> currentSection = ValueNotifier<int>(
      AppSectionScope.searchSectionIndex,
    );
    addTearDown(currentSection.dispose);

    await _pumpRetainedSearch(tester, dataSource, currentSection);

    await tester.enterText(find.byType(TextField), 'radio');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Radio result'), findsOneWidget);

    currentSection.value = 0;
    await tester.pump();
    dataSource.deferNext = true;
    currentSection.value = AppSectionScope.searchSectionIndex;
    await tester.pump();
    await tester.pump();

    expect(dataSource.calls, 2);
    expect(dataSource.hasDeferredSearch, isTrue);

    await tester.enterText(find.byType(TextField), 'antenna');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(dataSource.calls, 3);
    expect(find.text('Antenna result'), findsOneWidget);

    dataSource.completeDeferredWith('Stale radio result');
    await tester.pump();
    await tester.pump();

    expect(find.text('Antenna result'), findsOneWidget);
    expect(find.text('Stale radio result'), findsNothing);
  });
}

Future<void> _pumpRetainedSearch(
  WidgetTester tester,
  SearchJournalDataSource dataSource,
  ValueNotifier<int> currentSection,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchJournalDataSourceProvider.overrideWithValue(dataSource),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AppSectionScope(
            currentIndex: currentSection,
            child: const SearchScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

final class _MutableSearchJournal implements SearchJournalDataSource {
  int calls = 0;
  bool completed = false;

  @override
  Future<List<JournalSearchResult>> search(
    String query, {
    Set<JournalSignifier> signifiers = const <JournalSignifier>{},
  }) async {
    calls++;
    return <JournalSearchResult>[
      JournalSearchResult(
        entryId: 'entry-1',
        type: JournalEntryType.task,
        taskState: completed
            ? JournalTaskState.completed
            : JournalTaskState.open,
        content: 'Radio check',
        ownerKind: SearchOwnerKind.log,
        ownerId: 'daily-1',
        updatedAtUtcMicros: calls,
        logKind: JournalLogKind.daily,
        periodStart: '2026-09-03',
      ),
    ];
  }
}

final class _RaceSearchJournal implements SearchJournalDataSource {
  int calls = 0;
  bool deferNext = false;
  Completer<List<JournalSearchResult>>? _deferred;

  bool get hasDeferredSearch => _deferred != null;

  @override
  Future<List<JournalSearchResult>> search(
    String query, {
    Set<JournalSignifier> signifiers = const <JournalSignifier>{},
  }) {
    calls++;
    if (deferNext) {
      deferNext = false;
      final Completer<List<JournalSearchResult>> completer =
          Completer<List<JournalSearchResult>>();
      _deferred = completer;
      return completer.future;
    }

    return Future<List<JournalSearchResult>>.value(<JournalSearchResult>[
      _result(query == 'antenna' ? 'Antenna result' : 'Radio result'),
    ]);
  }

  void completeDeferredWith(String content) {
    final Completer<List<JournalSearchResult>> completer = _deferred!;
    _deferred = null;
    completer.complete(<JournalSearchResult>[_result(content)]);
  }

  JournalSearchResult _result(String content) {
    return JournalSearchResult(
      entryId: 'entry-$calls',
      type: JournalEntryType.note,
      taskState: null,
      content: content,
      ownerKind: SearchOwnerKind.log,
      ownerId: 'daily-1',
      updatedAtUtcMicros: calls,
      logKind: JournalLogKind.daily,
      periodStart: '2026-09-03',
    );
  }
}
