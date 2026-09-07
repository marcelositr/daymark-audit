import 'package:daymark/features/journal/data/search_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:daymark/features/journal/presentation/search_screen.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('searches explicitly and renders method-native owner context', (
    tester,
  ) async {
    final _MemorySearchJournal dataSource = _MemorySearchJournal(
      results: <JournalSearchResult>[
        const JournalSearchResult(
          entryId: 'entry-1',
          type: JournalEntryType.task,
          taskState: JournalTaskState.open,
          content: 'Radio check',
          ownerKind: SearchOwnerKind.log,
          ownerId: 'daily-1',
          updatedAtUtcMicros: 4,
          logKind: JournalLogKind.daily,
          periodStart: '2026-09-03',
        ),
        const JournalSearchResult(
          entryId: 'entry-2',
          type: JournalEntryType.event,
          taskState: null,
          content: 'Radio club meeting',
          ownerKind: SearchOwnerKind.log,
          ownerId: 'monthly-1',
          updatedAtUtcMicros: 3,
          logKind: JournalLogKind.monthly,
          periodStart: '2026-09-01',
          monthlySection: JournalMonthlySection.calendar,
          monthlyCalendarDate: '2026-09-12',
        ),
        const JournalSearchResult(
          entryId: 'entry-3',
          type: JournalEntryType.note,
          taskState: null,
          content: 'Future radio note',
          ownerKind: SearchOwnerKind.log,
          ownerId: 'future-1',
          updatedAtUtcMicros: 2,
          logKind: JournalLogKind.future,
          periodStart: '2026-10-01',
        ),
        const JournalSearchResult(
          entryId: 'entry-4',
          type: JournalEntryType.note,
          taskState: null,
          content: 'Radio frequencies',
          ownerKind: SearchOwnerKind.collection,
          ownerId: 'collection-1',
          updatedAtUtcMicros: 1,
          collectionTitle: 'Radio',
        ),
      ],
    );

    await _pumpSearch(tester, dataSource);

    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  radio  ');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
    await tester.pumpAndSettle();

    expect(dataSource.lastQuery, 'radio');
    expect(find.text('Radio check'), findsOneWidget);
    expect(find.text('Radio club meeting'), findsOneWidget);
    expect(find.text('Future radio note'), findsOneWidget);
    expect(find.text('Radio frequencies'), findsOneWidget);
    expect(find.textContaining('Daily:'), findsOneWidget);
    expect(find.textContaining('Monthly:'), findsOneWidget);
    expect(find.textContaining('Future:'), findsOneWidget);
    expect(find.text('Collections: Radio'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);

    final ListTile dailyTile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Radio check'),
        matching: find.byType(ListTile),
      ),
    );
    expect(dailyTile.onTap, isNotNull);
  });

  testWidgets('shows a quiet empty state when no entry matches', (
    tester,
  ) async {
    final _MemorySearchJournal dataSource = _MemorySearchJournal();

    await _pumpSearch(tester, dataSource);

    await tester.enterText(find.byType(TextField), 'missing');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(dataSource.lastQuery, 'missing');
    expect(find.text('No matching entries.'), findsOneWidget);
  });

  testWidgets('Linux search field regains focus after search completes', (
    tester,
  ) async {
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    final _MemorySearchJournal dataSource = _MemorySearchJournal();
    await _pumpSearch(tester, dataSource);
    await tester.pump();

    TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField), 'focus');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);

    debugDefaultTargetPlatformOverride = null;
  });
}

Future<void> _pumpSearch(
  WidgetTester tester,
  _MemorySearchJournal dataSource,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchJournalDataSourceProvider.overrideWithValue(dataSource),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SearchScreen()),
      ),
    ),
  );
  await tester.pump();
}

final class _MemorySearchJournal implements SearchJournalDataSource {
  _MemorySearchJournal({this._results = const <JournalSearchResult>[]});

  final List<JournalSearchResult> _results;
  String? lastQuery;

  @override
  Future<List<JournalSearchResult>> search(
    String query, {
    Set<JournalSignifier> signifiers = const <JournalSignifier>{},
  }) async {
    lastQuery = query;
    return List<JournalSearchResult>.unmodifiable(_results);
  }
}
