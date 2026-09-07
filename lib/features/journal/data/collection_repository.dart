import 'package:daymark/core/database/daymark_database.dart';
import 'package:daymark/features/journal/application/journal_service.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:drift/drift.dart';

final class CollectionSummary {
  const CollectionSummary({required this.id, required this.title});

  final String id;
  final String title;
}

final class CollectionEntry {
  const CollectionEntry({
    required this.id,
    required this.type,
    required this.taskState,
    required this.content,
    required this.ordinal,
  });

  final String id;
  final JournalEntryType type;
  final JournalTaskState? taskState;
  final String content;
  final int ordinal;
}

final class CollectionReferenceEntry {
  const CollectionReferenceEntry({
    required this.id,
    required this.type,
    required this.taskState,
    required this.content,
    required this.ordinal,
  });

  final String id;
  final JournalEntryType type;
  final JournalTaskState? taskState;
  final String content;
  final int ordinal;
}

final class CollectionSnapshot {
  CollectionSnapshot({
    required this.id,
    required this.title,
    required List<CollectionEntry> entries,
    List<CollectionReferenceEntry> references = const [],
  }) : entries = List<CollectionEntry>.unmodifiable(entries),
       references = List<CollectionReferenceEntry>.unmodifiable(references);

  final String id;
  final String title;
  final List<CollectionEntry> entries;
  final List<CollectionReferenceEntry> references;
}

/// Focused read/write boundary for Bullet Journal Collections.
///
/// Reads query encrypted storage directly. Mutations continue through the
/// semantic [JournalService], which owns entry placement/reference invariants.
final class CollectionRepository {
  const CollectionRepository(this._database, this._journalService);

  final DaymarkDatabase _database;
  final JournalService _journalService;

  Future<List<CollectionSummary>> list() async {
    final rows = await _database.customSelect('''
      SELECT id, title
      FROM collections
      ORDER BY created_at DESC, id DESC
    ''').get();

    return <CollectionSummary>[
      for (final row in rows)
        CollectionSummary(
          id: row.read<String>('id'),
          title: row.read<String>('title'),
        ),
    ];
  }

  Future<String> create({required String title}) {
    return _journalService.createCollection(title: title);
  }

  Future<void> undoCreate(String collectionId) {
    return _journalService.undoCollectionCreation(collectionId: collectionId);
  }

  Future<CollectionSnapshot> load(String collectionId) async {
    final collection = await _database
        .customSelect(
          'SELECT id, title FROM collections WHERE id = ?',
          variables: <Variable<Object>>[Variable.withString(collectionId)],
        )
        .getSingleOrNull();
    if (collection == null) {
      throw JournalNotFoundException('Collection', collectionId);
    }

    final ownedRows = await _database
        .customSelect(
          '''
          SELECT
            e.id,
            e.entry_type,
            e.task_state,
            e.content,
            p.ordinal
          FROM entry_placements p
          JOIN entries e ON e.id = p.entry_id
          WHERE p.collection_id = ?
          ORDER BY p.ordinal
          ''',
          variables: <Variable<Object>>[Variable.withString(collectionId)],
        )
        .get();

    final referenceRows = await _database
        .customSelect(
          '''
          SELECT
            e.id,
            e.entry_type,
            e.task_state,
            e.content,
            r.ordinal
          FROM collection_references r
          JOIN entries e ON e.id = r.entry_id
          WHERE r.collection_id = ?
          ORDER BY r.ordinal
          ''',
          variables: <Variable<Object>>[Variable.withString(collectionId)],
        )
        .get();

    return CollectionSnapshot(
      id: collection.read<String>('id'),
      title: collection.read<String>('title'),
      entries: <CollectionEntry>[
        for (final row in ownedRows)
          CollectionEntry(
            id: row.read<String>('id'),
            type: _entryTypeFromCode(row.read<String>('entry_type')),
            taskState: _taskStateFromCode(
              row.readNullable<String>('task_state'),
            ),
            content: row.read<String>('content'),
            ordinal: row.read<int>('ordinal'),
          ),
      ],
      references: <CollectionReferenceEntry>[
        for (final row in referenceRows)
          CollectionReferenceEntry(
            id: row.read<String>('id'),
            type: _entryTypeFromCode(row.read<String>('entry_type')),
            taskState: _taskStateFromCode(
              row.readNullable<String>('task_state'),
            ),
            content: row.read<String>('content'),
            ordinal: row.read<int>('ordinal'),
          ),
      ],
    );
  }

  Future<void> capture({
    required String collectionId,
    required JournalEntryType type,
    required String content,
  }) async {
    await _journalService.capture(
      type: type,
      content: content,
      owner: JournalCollectionOwner(collectionId),
    );
  }

  Future<void> reference({
    required String collectionId,
    required String entryId,
  }) {
    return _journalService.referenceInCollection(
      collectionId: collectionId,
      entryId: entryId,
    );
  }

  Future<void> removeReference({
    required String collectionId,
    required String entryId,
  }) {
    return _journalService.removeReferenceFromCollection(
      collectionId: collectionId,
      entryId: entryId,
    );
  }
}

JournalEntryType _entryTypeFromCode(String code) => switch (code) {
  'task' => JournalEntryType.task,
  'event' => JournalEntryType.event,
  'note' => JournalEntryType.note,
  _ => throw JournalInvariantException('Unknown persisted entry type: $code.'),
};

JournalTaskState? _taskStateFromCode(String? code) => switch (code) {
  null => null,
  'open' => JournalTaskState.open,
  'completed' => JournalTaskState.completed,
  'migrated' => JournalTaskState.migrated,
  'scheduled' => JournalTaskState.scheduled,
  'discarded' => JournalTaskState.discarded,
  _ => throw JournalInvariantException('Unknown persisted task state: $code.'),
};
