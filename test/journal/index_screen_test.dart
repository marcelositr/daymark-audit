import 'package:daymark/features/journal/data/index_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:daymark/features/journal/presentation/index_screen.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('adds an existing journal structure to the Index', (
    tester,
  ) async {
    final _MemoryIndexJournal dataSource = _MemoryIndexJournal(
      candidates: <IndexCandidate>[
        const IndexCandidate(
          targetKind: IndexTargetKind.collection,
          targetId: 'collection-1',
          collectionTitle: 'Radio',
        ),
      ],
    );

    await _pumpIndex(tester, dataSource);

    expect(find.text('Nothing indexed yet.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Add to Index'), findsOneWidget);
    expect(find.text('Collections: Radio'), findsOneWidget);

    await tester.tap(find.text('Collections: Radio'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing indexed yet.'), findsNothing);
    expect(find.text('Collections: Radio'), findsOneWidget);
    expect(dataSource.items.single.ordinal, 0);
  });

  testWidgets('renders indexed Logs with method-native labels', (tester) async {
    final _MemoryIndexJournal dataSource = _MemoryIndexJournal(
      items: <IndexItem>[
        const IndexItem(
          id: 'index-1',
          ordinal: 0,
          targetKind: IndexTargetKind.log,
          targetId: 'daily-1',
          logKind: JournalLogKind.daily,
          periodStart: '2026-09-03',
        ),
        const IndexItem(
          id: 'index-2',
          ordinal: 1,
          targetKind: IndexTargetKind.log,
          targetId: 'monthly-1',
          logKind: JournalLogKind.monthly,
          periodStart: '2026-09-01',
        ),
      ],
    );

    await _pumpIndex(tester, dataSource);

    expect(find.textContaining('Daily:'), findsOneWidget);
    expect(find.textContaining('Monthly:'), findsOneWidget);
  });
  testWidgets('Index items can be deliberately reordered and removed', (
    tester,
  ) async {
    final _MemoryIndexJournal dataSource = _MemoryIndexJournal(
      items: <IndexItem>[
        const IndexItem(
          id: 'index-1',
          ordinal: 0,
          targetKind: IndexTargetKind.collection,
          targetId: 'first',
          collectionTitle: 'First',
        ),
        const IndexItem(
          id: 'index-2',
          ordinal: 1,
          targetKind: IndexTargetKind.collection,
          targetId: 'second',
          collectionTitle: 'Second',
        ),
      ],
    );

    await _pumpIndex(tester, dataSource);

    final ListTile firstTile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Collections: First'),
        matching: find.byType(ListTile),
      ),
    );
    expect(firstTile.onTap, isNotNull);

    await tester.tap(find.byTooltip('Index item actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move down'));
    await tester.pumpAndSettle();

    expect(dataSource.items.first.id, 'index-2');
    expect(dataSource.items.last.id, 'index-1');

    await tester.tap(find.byTooltip('Index item actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(dataSource.items, hasLength(1));
    expect(dataSource.items.single.id, 'index-2');
    expect(dataSource.items.single.ordinal, 0);
  });
}

Future<void> _pumpIndex(
  WidgetTester tester,
  _MemoryIndexJournal dataSource,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [indexJournalDataSourceProvider.overrideWithValue(dataSource)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: IndexScreen()),
      ),
    ),
  );
  await tester.pump();
}

final class _MemoryIndexJournal implements IndexJournalDataSource {
  _MemoryIndexJournal({
    List<IndexItem> items = const <IndexItem>[],
    List<IndexCandidate> candidates = const <IndexCandidate>[],
  }) : items = List<IndexItem>.from(items),
       _candidates = List<IndexCandidate>.from(candidates);

  final List<IndexItem> items;
  final List<IndexCandidate> _candidates;

  @override
  Future<List<IndexItem>> list() async => List<IndexItem>.unmodifiable(items);

  @override
  Future<List<IndexCandidate>> candidates() async {
    return List<IndexCandidate>.unmodifiable(_candidates);
  }

  @override
  Future<void> add(IndexCandidate candidate) async {
    _candidates.remove(candidate);
    items.add(
      IndexItem(
        id: 'index-${items.length + 1}',
        ordinal: items.length,
        targetKind: candidate.targetKind,
        targetId: candidate.targetId,
        logKind: candidate.logKind,
        periodStart: candidate.periodStart,
        collectionTitle: candidate.collectionTitle,
      ),
    );
  }

  @override
  Future<void> move({required String itemId, required int newOrdinal}) async {
    final int current = items.indexWhere((item) => item.id == itemId);
    if (current < 0) {
      throw StateError('Missing Index item.');
    }
    final IndexItem item = items.removeAt(current);
    items.insert(newOrdinal, item);
    _normalizeOrdinals();
  }

  @override
  Future<void> remove({required String itemId}) async {
    items.removeWhere((item) => item.id == itemId);
    _normalizeOrdinals();
  }

  void _normalizeOrdinals() {
    for (int index = 0; index < items.length; index++) {
      final IndexItem source = items[index];
      items[index] = IndexItem(
        id: source.id,
        ordinal: index,
        targetKind: source.targetKind,
        targetId: source.targetId,
        logKind: source.logKind,
        periodStart: source.periodStart,
        collectionTitle: source.collectionTitle,
      );
    }
  }
}
