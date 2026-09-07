import 'package:daymark/features/journal/data/future_log_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:daymark/features/journal/presentation/future_history_screen.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('exact Future source is read-only and non-composing', (
    tester,
  ) async {
    final _FutureHistoryDataSource dataSource = _FutureHistoryDataSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          futureHistoryDataSourceProvider.overrideWithValue(dataSource),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: FutureHistoryScreen(periodStart: '2026-10-01')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(dataSource.requestedPeriod, '2026-10-01');
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('This Future Log is read-only.'), findsOneWidget);
    expect(find.text('Persisted future note'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
  });
}

final class _FutureHistoryDataSource implements FutureHistoryDataSource {
  String? requestedPeriod;

  @override
  Future<void> completeTask({required String entryId}) async {}

  @override
  Future<void> discardTask({required String entryId}) async {}

  @override
  Future<FutureLogSnapshot?> find(String periodStart) async {
    requestedPeriod = periodStart;
    return FutureLogSnapshot(
      logId: 'future-october',
      periodStart: periodStart,
      entries: const [
        FutureLogEntry(
          id: 'note-1',
          type: JournalEntryType.note,
          taskState: null,
          content: 'Persisted future note',
          ordinal: 0,
        ),
      ],
    );
  }
}
