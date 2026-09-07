import 'package:daymark/core/database/daymark_database.dart';
import 'package:daymark/features/journal/application/journal_service.dart';
import 'package:daymark/features/journal/data/journal_repository.dart';
import 'package:daymark/features/journal/data/search_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DaymarkDatabase database;
  late JournalService service;
  late JournalSearchRepository search;
  late _IdSequence ids;

  setUp(() {
    database = DaymarkDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    ids = _IdSequence();
    service = JournalService(
      JournalRepository(
        database,
        idGenerator: ids.next,
        nowUtcMicros: () => 1_000_000,
      ),
    );
    search = JournalSearchRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'finds entries across Logs and Collections with owning context',
    () async {
      final String dailyId = await service.createLog(
        kind: JournalLogKind.daily,
        periodStart: '2026-09-03',
      );
      final String monthlyId = await service.createLog(
        kind: JournalLogKind.monthly,
        periodStart: '2026-09-01',
      );
      final String futureId = await service.createLog(
        kind: JournalLogKind.future,
        periodStart: '2026-10-01',
      );
      final String collectionId = await service.createCollection(
        title: 'Radio',
      );

      await service.capture(
        type: JournalEntryType.task,
        content: 'Radio check',
        owner: JournalLogOwner(logId: dailyId),
      );
      await service.capture(
        type: JournalEntryType.event,
        content: 'Radio club meeting',
        owner: JournalLogOwner(
          logId: monthlyId,
          monthlySection: JournalMonthlySection.calendar,
          monthlyCalendarDate: '2026-09-12',
        ),
      );
      await service.capture(
        type: JournalEntryType.note,
        content: 'RADIO trip notes',
        owner: JournalLogOwner(logId: futureId),
      );
      await service.capture(
        type: JournalEntryType.note,
        content: 'Radio frequencies',
        owner: JournalCollectionOwner(collectionId),
      );

      final List<JournalSearchResult> results = await search.search('radio');

      expect(results, hasLength(4));

      final JournalSearchResult daily = results.singleWhere(
        (result) => result.content == 'Radio check',
      );
      expect(daily.ownerKind, SearchOwnerKind.log);
      expect(daily.logKind, JournalLogKind.daily);
      expect(daily.periodStart, '2026-09-03');
      expect(daily.type, JournalEntryType.task);
      expect(daily.taskState, JournalTaskState.open);

      final JournalSearchResult monthly = results.singleWhere(
        (result) => result.content == 'Radio club meeting',
      );
      expect(monthly.logKind, JournalLogKind.monthly);
      expect(monthly.monthlySection, JournalMonthlySection.calendar);
      expect(monthly.monthlyCalendarDate, '2026-09-12');

      final JournalSearchResult future = results.singleWhere(
        (result) => result.content == 'RADIO trip notes',
      );
      expect(future.logKind, JournalLogKind.future);
      expect(future.periodStart, '2026-10-01');

      final JournalSearchResult collection = results.singleWhere(
        (result) => result.content == 'Radio frequencies',
      );
      expect(collection.ownerKind, SearchOwnerKind.collection);
      expect(collection.ownerId, collectionId);
      expect(collection.collectionTitle, 'Radio');
    },
  );

  test('matches Unicode case changes while keeping accents literal', () async {
    final String dailyId = await service.createLog(
      kind: JournalLogKind.daily,
      periodStart: '2026-09-03',
    );
    await service.capture(
      type: JournalEntryType.note,
      content: 'Revisar RÁDIO portátil',
      owner: JournalLogOwner(logId: dailyId),
    );

    final List<JournalSearchResult> lower = await search.search('rádio');
    final List<JournalSearchResult> upper = await search.search('RÁDIO');

    expect(lower.single.content, 'Revisar RÁDIO portátil');
    expect(upper.single.content, 'Revisar RÁDIO portátil');
    expect(await search.search('radio'), isEmpty);
  });

  test('filters by one or more Signifiers without requiring text', () async {
    final String dailyId = await service.createLog(
      kind: JournalLogKind.daily,
      periodStart: '2026-09-03',
    );
    final String priorityOnly = await service.capture(
      type: JournalEntryType.task,
      content: 'Priority only',
      owner: JournalLogOwner(logId: dailyId),
    );
    final String both = await service.capture(
      type: JournalEntryType.note,
      content: 'Priority and inspiration',
      owner: JournalLogOwner(logId: dailyId),
    );
    await service.replaceEntrySignifiers(
      entryId: priorityOnly,
      signifiers: const <JournalSignifier>{JournalSignifier.priority},
    );
    await service.replaceEntrySignifiers(
      entryId: both,
      signifiers: const <JournalSignifier>{
        JournalSignifier.priority,
        JournalSignifier.inspiration,
      },
    );

    final List<JournalSearchResult> priority = await search.search(
      '',
      signifiers: const <JournalSignifier>{JournalSignifier.priority},
    );
    final List<JournalSearchResult> bothFilters = await search.search(
      '',
      signifiers: const <JournalSignifier>{
        JournalSignifier.priority,
        JournalSignifier.inspiration,
      },
    );

    expect(priority, hasLength(2));
    expect(bothFilters, hasLength(1));
    expect(bothFilters.single.entryId, both);
    expect(
      bothFilters.single.signifiers,
      containsAll(<JournalSignifier>[
        JournalSignifier.priority,
        JournalSignifier.inspiration,
      ]),
    );
  });

  test(
    'treats query punctuation literally and ignores blank queries',
    () async {
      final String dailyId = await service.createLog(
        kind: JournalLogKind.daily,
        periodStart: '2026-09-03',
      );
      await service.capture(
        type: JournalEntryType.note,
        content: 'Battery at 100%',
        owner: JournalLogOwner(logId: dailyId),
      );
      await service.capture(
        type: JournalEntryType.note,
        content: 'Battery at 100 percent',
        owner: JournalLogOwner(logId: dailyId),
      );

      final List<JournalSearchResult> percent = await search.search('%');

      expect(percent, hasLength(1));
      expect(percent.single.content, 'Battery at 100%');
      expect(await search.search('   '), isEmpty);
    },
  );
}

final class _IdSequence {
  int _value = 1;

  String next() {
    final String suffix = _value.toString().padLeft(12, '0');
    _value++;
    return '00000000-0000-7000-8000-$suffix';
  }
}
