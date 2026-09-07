import 'package:daymark/features/journal/data/daily_log_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:daymark/features/journal/presentation/daily_history_screen.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('historical Daily Logs are read-only and browse day by day', (
    tester,
  ) async {
    final _MemoryDailyHistory dataSource = _MemoryDailyHistory(
      snapshots: <String, DailyLogSnapshot>{
        '2026-09-02': DailyLogSnapshot(
          logId: 'daily-1',
          methodDate: '2026-09-02',
          entries: const <DailyLogEntry>[
            DailyLogEntry(
              id: 'entry-1',
              type: JournalEntryType.task,
              taskState: JournalTaskState.open,
              content: 'Past task',
              ordinal: 0,
            ),
          ],
        ),
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyHistoryDataSourceProvider.overrideWithValue(dataSource),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DailyHistoryScreen(
              methodDate: '2026-09-02',
              now: () => DateTime(2026, 9, 4),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(dataSource.calls, <String>['2026-09-02']);
    expect(find.text('Past task'), findsOneWidget);
    expect(find.text('Historical Daily Logs are read-only.'), findsOneWidget);
    expect(find.byTooltip('Today'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(PopupMenuButton<dynamic>), findsNothing);

    IconButton next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(next.onPressed, isNotNull);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(dataSource.calls, <String>['2026-09-02', '2026-09-03']);
    expect(find.text('Nothing was logged on this day.'), findsOneWidget);
    next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(next.onPressed, isNotNull);
  });

  testWidgets('an empty historical day stays quiet and non-interactive', (
    tester,
  ) async {
    final _MemoryDailyHistory dataSource = _MemoryDailyHistory();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyHistoryDataSourceProvider.overrideWithValue(dataSource),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DailyHistoryScreen(
              methodDate: '2026-09-01',
              now: () => DateTime(2026, 9, 4),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing was logged on this day.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(PopupMenuButton<dynamic>), findsNothing);
  });
}

final class _MemoryDailyHistory implements DailyHistoryDataSource {
  _MemoryDailyHistory({this.snapshots = const <String, DailyLogSnapshot>{}});

  final Map<String, DailyLogSnapshot> snapshots;
  final List<String> calls = <String>[];

  @override
  Future<DailyLogSnapshot?> find(String methodDate) async {
    calls.add(methodDate);
    return snapshots[methodDate];
  }
}
