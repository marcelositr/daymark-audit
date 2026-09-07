import 'package:daymark/core/database/daymark_database.dart';
import 'package:daymark/features/journal/application/journal_service.dart';
import 'package:daymark/features/journal/data/collection_repository.dart';
import 'package:daymark/features/journal/data/journal_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DaymarkDatabase database;
  late CollectionRepository collections;
  late JournalService service;
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
    collections = CollectionRepository(database, service);
  });

  tearDown(() async {
    await database.close();
  });

  test('lists newest Collections first', () async {
    await collections.create(title: 'Books');
    await collections.create(title: 'Garden');

    final result = await collections.list();

    expect(result, hasLength(2));
    expect(result[0].title, 'Garden');
    expect(result[1].title, 'Books');
  });

  test('undoes creation only while a Collection remains empty', () async {
    final String emptyId = await collections.create(title: 'Mistake');

    await collections.undoCreate(emptyId);

    expect(await collections.list(), isEmpty);

    final String usedId = await collections.create(title: 'Used');
    await collections.capture(
      collectionId: usedId,
      type: JournalEntryType.note,
      content: 'Keep this',
    );

    await expectLater(
      collections.undoCreate(usedId),
      throwsA(isA<JournalInvariantException>()),
    );
    expect((await collections.load(usedId)).entries, hasLength(1));
  });

  test('captures Task Event and Note as Collection-owned entries', () async {
    final String id = await collections.create(title: 'Trip');

    await collections.capture(
      collectionId: id,
      type: JournalEntryType.task,
      content: 'Pack radio',
    );
    await collections.capture(
      collectionId: id,
      type: JournalEntryType.event,
      content: 'Train at 08:00',
    );
    await collections.capture(
      collectionId: id,
      type: JournalEntryType.note,
      content: 'Platform 4',
    );

    final CollectionSnapshot snapshot = await collections.load(id);

    expect(snapshot.title, 'Trip');
    expect(snapshot.entries, hasLength(3));
    expect(snapshot.entries[0].type, JournalEntryType.task);
    expect(snapshot.entries[0].taskState, JournalTaskState.open);
    expect(snapshot.entries[1].type, JournalEntryType.event);
    expect(snapshot.entries[1].taskState, isNull);
    expect(snapshot.entries[2].type, JournalEntryType.note);
    expect(snapshot.entries[2].taskState, isNull);

    final placementCount = await database
        .customSelect(
          'SELECT COUNT(*) AS count FROM entry_placements WHERE collection_id = ?',
          variables: <Variable<Object>>[Variable.withString(id)],
        )
        .getSingle();
    expect(placementCount.read<int>('count'), 3);
  });

  test(
    'loads references separately without changing source ownership',
    () async {
      final String collectionId = await collections.create(title: 'Reading');
      final String dailyLogId = await service.createLog(
        kind: JournalLogKind.daily,
        periodStart: '2026-09-03',
      );
      final String entryId = await service.capture(
        type: JournalEntryType.task,
        content: 'Read linked article',
        owner: JournalLogOwner(logId: dailyLogId),
      );

      await collections.reference(collectionId: collectionId, entryId: entryId);

      final CollectionSnapshot snapshot = await collections.load(collectionId);
      expect(snapshot.entries, isEmpty);
      expect(snapshot.references, hasLength(1));
      expect(snapshot.references.single.id, entryId);
      expect(snapshot.references.single.taskState, JournalTaskState.open);
      expect(snapshot.references.single.content, 'Read linked article');

      final placement = await database
          .customSelect(
            'SELECT log_id, collection_id FROM entry_placements WHERE entry_id = ?',
            variables: <Variable<Object>>[Variable.withString(entryId)],
          )
          .getSingle();
      expect(placement.read<String>('log_id'), dailyLogId);
      expect(placement.readNullable<String>('collection_id'), isNull);
    },
  );

  test(
    'unknown Collection rejects capture without partial entry write',
    () async {
      expect(
        () => collections.capture(
          collectionId: '00000000-0000-7000-8000-999999999999',
          type: JournalEntryType.note,
          content: 'Must not persist',
        ),
        throwsA(isA<JournalNotFoundException>()),
      );

      final count = await database
          .customSelect('SELECT COUNT(*) AS count FROM entries')
          .getSingle();
      expect(count.read<int>('count'), 0);
    },
  );
  test('removing a Collection reference preserves source ownership and compacts order', () async {
    final String collectionId = await collections.create(title: 'Links');
    final String dailyLogId = await service.createLog(
      kind: JournalLogKind.daily,
      periodStart: '2026-09-03',
    );
    final String firstEntryId = await service.capture(
      type: JournalEntryType.note,
      content: 'First linked note',
      owner: JournalLogOwner(logId: dailyLogId),
    );
    final String secondEntryId = await service.capture(
      type: JournalEntryType.note,
      content: 'Second linked note',
      owner: JournalLogOwner(logId: dailyLogId),
    );

    await collections.reference(
      collectionId: collectionId,
      entryId: firstEntryId,
    );
    await collections.reference(
      collectionId: collectionId,
      entryId: secondEntryId,
    );

    await collections.removeReference(
      collectionId: collectionId,
      entryId: firstEntryId,
    );

    final CollectionSnapshot snapshot = await collections.load(collectionId);
    expect(snapshot.references, hasLength(1));
    expect(snapshot.references.single.id, secondEntryId);
    expect(snapshot.references.single.ordinal, 0);

    final placement = await database
        .customSelect(
          'SELECT log_id, collection_id FROM entry_placements WHERE entry_id = ?',
          variables: <Variable<Object>>[Variable.withString(secondEntryId)],
        )
        .getSingle();
    expect(placement.read<String>('log_id'), dailyLogId);
    expect(placement.readNullable<String>('collection_id'), isNull);
  });
}

final class _IdSequence {
  int _value = 1;

  String next() {
    final String suffix = _value.toString().padLeft(12, '0');
    _value++;
    return '00000000-0000-7000-8000-$suffix';
  }
}
