import 'package:daymark/core/database/daymark_database.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

final class JournalRepository {
  JournalRepository(
    this._database, {
    String Function()? idGenerator,
    int Function()? nowUtcMicros,
  }) : _idGenerator = idGenerator ?? _defaultIdGenerator,
       _nowUtcMicros = nowUtcMicros ?? _defaultNowUtcMicros;

  final DaymarkDatabase _database;
  final String Function() _idGenerator;
  final int Function() _nowUtcMicros;

  Future<String> createLog({
    required JournalLogKind kind,
    required String periodStart,
  }) {
    return _database.transaction(() async {
      _validateLogPeriod(kind, periodStart);

      final existing = await _database
          .customSelect(
            '''
        SELECT id
        FROM logs
        WHERE kind = ? AND period_start = ?
        ''',
            variables: <Variable<Object>>[
              Variable.withString(kind.code),
              Variable.withString(periodStart),
            ],
          )
          .getSingleOrNull();
      if (existing != null) {
        throw JournalInvariantException(
          'A ${kind.code} log already exists for $periodStart.',
        );
      }

      final String id = _newId();
      await _database.customStatement(
        '''
        INSERT INTO logs (id, kind, period_start, created_at)
        VALUES (?, ?, ?, ?)
        ''',
        <Object>[id, kind.code, periodStart, _now()],
      );
      return id;
    });
  }

  Future<String> createCollection({required String title}) {
    return _database.transaction(() async {
      if (title.trim().isEmpty) {
        throw const JournalInvariantException(
          'Collection title must not be blank.',
        );
      }

      final int now = _now();
      final String id = _newId();
      await _database.customStatement(
        '''
        INSERT INTO collections (id, title, created_at, updated_at)
        VALUES (?, ?, ?, ?)
        ''',
        <Object>[id, title, now, now],
      );
      return id;
    });
  }

  Future<void> undoCollectionCreation({required String collectionId}) {
    return _database.transaction(() async {
      final collection = await _database
          .customSelect(
            '''
            SELECT created_at, updated_at
            FROM collections
            WHERE id = ?
            ''',
            variables: <Variable<Object>>[Variable.withString(collectionId)],
          )
          .getSingleOrNull();
      if (collection == null) {
        throw JournalNotFoundException('Collection', collectionId);
      }

      if (collection.read<int>('created_at') !=
          collection.read<int>('updated_at')) {
        throw const JournalInvariantException(
          'Only an untouched Collection can be undone.',
        );
      }

      final relations = await _database
          .customSelect(
            '''
            SELECT
              EXISTS(
                SELECT 1 FROM entry_placements WHERE collection_id = ?
              ) AS has_entries,
              EXISTS(
                SELECT 1 FROM collection_references WHERE collection_id = ?
              ) AS has_references,
              EXISTS(
                SELECT 1 FROM index_items WHERE collection_id = ?
              ) AS is_indexed
            ''',
            variables: <Variable<Object>>[
              Variable.withString(collectionId),
              Variable.withString(collectionId),
              Variable.withString(collectionId),
            ],
          )
          .getSingle();

      if (relations.read<int>('has_entries') != 0 ||
          relations.read<int>('has_references') != 0 ||
          relations.read<int>('is_indexed') != 0) {
        throw const JournalInvariantException(
          'A Collection with journal relationships cannot be undone.',
        );
      }

      await _database.customStatement(
        'DELETE FROM collections WHERE id = ?',
        <Object>[collectionId],
      );
    });
  }

  Future<String> createEntry({
    required JournalEntryType type,
    required String content,
    required JournalEntryOwner owner,
  }) {
    return _database.transaction(() async {
      if (content.trim().isEmpty) {
        throw const JournalInvariantException(
          'Entry content must not be blank.',
        );
      }

      final _ResolvedOwner resolvedOwner = await _resolveOwner(owner);
      final int ordinal = await _nextPlacementOrdinal(resolvedOwner);
      final int now = _now();
      final String id = _newId();

      await _insertEntry(
        id: id,
        type: type,
        taskState: type == JournalEntryType.task ? JournalTaskState.open : null,
        content: content,
        now: now,
      );
      await _insertPlacement(
        entryId: id,
        owner: resolvedOwner,
        ordinal: ordinal,
      );
      return id;
    });
  }

  Future<void> undoCapture({required String entryId}) {
    return _database.transaction(() async {
      final entry = await _database
          .customSelect(
            '''
        SELECT entry_type, task_state, created_at, updated_at
        FROM entries
        WHERE id = ?
        ''',
            variables: <Variable<Object>>[Variable.withString(entryId)],
          )
          .getSingleOrNull();
      if (entry == null) {
        throw JournalNotFoundException('Entry', entryId);
      }

      final JournalEntryType type = _entryTypeFromCode(
        entry.read<String>('entry_type'),
      );
      final JournalTaskState? taskState = _taskStateFromCode(
        entry.readNullable<String>('task_state'),
      );
      if (entry.read<int>('created_at') != entry.read<int>('updated_at') ||
          (type == JournalEntryType.task &&
              taskState != JournalTaskState.open)) {
        throw const JournalInvariantException(
          'Only an untouched capture can be undone.',
        );
      }

      final relations = await _database
          .customSelect(
            '''
        SELECT
          EXISTS(
            SELECT 1 FROM migrations
            WHERE source_entry_id = ? OR destination_entry_id = ?
          ) AS has_migration,
          EXISTS(
            SELECT 1 FROM collection_references WHERE entry_id = ?
          ) AS has_reference,
          EXISTS(
            SELECT 1 FROM entry_signifiers WHERE entry_id = ?
          ) AS has_signifier
        ''',
            variables: <Variable<Object>>[
              Variable.withString(entryId),
              Variable.withString(entryId),
              Variable.withString(entryId),
              Variable.withString(entryId),
            ],
          )
          .getSingle();

      if (relations.read<int>('has_migration') != 0 ||
          relations.read<int>('has_reference') != 0 ||
          relations.read<int>('has_signifier') != 0) {
        throw const JournalInvariantException(
          'A capture with journal relationships cannot be undone.',
        );
      }

      await _database.customStatement(
        'DELETE FROM entry_placements WHERE entry_id = ?',
        <Object>[entryId],
      );
      await _database.customStatement(
        'DELETE FROM entries WHERE id = ?',
        <Object>[entryId],
      );
    });
  }

  Future<void> addCollectionReference({
    required String collectionId,
    required String entryId,
  }) {
    return _database.transaction(() async {
      await _requireCollection(collectionId);
      final _EntryRecord entry = await _requireEntry(entryId);
      final _PlacementRecord placement = await _requirePlacement(entryId);

      if (placement.collectionId == collectionId) {
        throw const JournalInvariantException(
          'An entry cannot reference the Collection that already owns it.',
        );
      }

      final duplicate = await _database
          .customSelect(
            '''
        SELECT 1
        FROM collection_references
        WHERE collection_id = ? AND entry_id = ?
        ''',
            variables: <Variable<Object>>[
              Variable.withString(collectionId),
              Variable.withString(entry.id),
            ],
          )
          .getSingleOrNull();
      if (duplicate != null) {
        throw const JournalInvariantException(
          'This Collection already references the entry.',
        );
      }

      final row = await _database
          .customSelect(
            '''
        SELECT COALESCE(MAX(ordinal), -1) + 1 AS next_ordinal
        FROM collection_references
        WHERE collection_id = ?
        ''',
            variables: <Variable<Object>>[Variable.withString(collectionId)],
          )
          .getSingle();

      await _database.customStatement(
        '''
        INSERT INTO collection_references (
          collection_id, entry_id, ordinal, created_at
        ) VALUES (?, ?, ?, ?)
        ''',
        <Object>[collectionId, entry.id, row.read<int>('next_ordinal'), _now()],
      );
    });
  }

  Future<void> removeCollectionReference({
    required String collectionId,
    required String entryId,
  }) {
    return _database.transaction(() async {
      await _requireCollection(collectionId);

      final existing = await _database
          .customSelect(
            '''
        SELECT 1
        FROM collection_references
        WHERE collection_id = ? AND entry_id = ?
        ''',
            variables: <Variable<Object>>[
              Variable.withString(collectionId),
              Variable.withString(entryId),
            ],
          )
          .getSingleOrNull();
      if (existing == null) {
        throw JournalNotFoundException('Collection reference', entryId);
      }

      await _database.customStatement(
        '''
        DELETE FROM collection_references
        WHERE collection_id = ? AND entry_id = ?
        ''',
        <Object>[collectionId, entryId],
      );

      final rows = await _database
          .customSelect(
            '''
        SELECT entry_id
        FROM collection_references
        WHERE collection_id = ?
        ORDER BY ordinal, entry_id
        ''',
            variables: <Variable<Object>>[Variable.withString(collectionId)],
          )
          .get();

      final List<String> orderedEntryIds = <String>[
        for (final row in rows) row.read<String>('entry_id'),
      ];
      if (orderedEntryIds.isEmpty) {
        return;
      }

      final maxRow = await _database
          .customSelect(
            '''
        SELECT COALESCE(MAX(ordinal), -1) AS max_ordinal
        FROM collection_references
        WHERE collection_id = ?
        ''',
            variables: <Variable<Object>>[Variable.withString(collectionId)],
          )
          .getSingle();
      final int temporaryBase =
          maxRow.read<int>('max_ordinal') + orderedEntryIds.length + 1;

      for (int index = 0; index < orderedEntryIds.length; index++) {
        await _database.customStatement(
          '''
          UPDATE collection_references
          SET ordinal = ?
          WHERE collection_id = ? AND entry_id = ?
          ''',
          <Object>[temporaryBase + index, collectionId, orderedEntryIds[index]],
        );
      }
      for (int index = 0; index < orderedEntryIds.length; index++) {
        await _database.customStatement(
          '''
          UPDATE collection_references
          SET ordinal = ?
          WHERE collection_id = ? AND entry_id = ?
          ''',
          <Object>[index, collectionId, orderedEntryIds[index]],
        );
      }
    });
  }

  Future<Set<JournalSignifier>> listEntrySignifiers({
    required String entryId,
  }) async {
    await _requireEntry(entryId);
    final rows = await _database
        .customSelect(
          '''
          SELECT s.builtin_code
          FROM entry_signifiers es
          JOIN signifiers s ON s.id = es.signifier_id
          WHERE es.entry_id = ? AND s.kind = 'builtin'
          ORDER BY s.builtin_code
          ''',
          variables: <Variable<Object>>[Variable.withString(entryId)],
        )
        .get();
    return <JournalSignifier>{
      for (final row in rows)
        journalSignifierFromCode(row.read<String>('builtin_code')),
    };
  }

  Future<void> replaceEntrySignifiers({
    required String entryId,
    required Set<JournalSignifier> signifiers,
  }) {
    return _database.transaction(() async {
      await _requireEntry(entryId);
      final Map<JournalSignifier, String> ids = <JournalSignifier, String>{};
      for (final JournalSignifier signifier in signifiers) {
        final existing = await _database
            .customSelect(
              '''
              SELECT id
              FROM signifiers
              WHERE kind = 'builtin' AND builtin_code = ?
              ''',
              variables: <Variable<Object>>[
                Variable.withString(signifier.code),
              ],
            )
            .getSingleOrNull();
        if (existing != null) {
          ids[signifier] = existing.read<String>('id');
          continue;
        }
        final String id = _newId();
        await _database.customStatement(
          '''
          INSERT INTO signifiers (
            id, kind, builtin_code, custom_label, custom_symbol, created_at
          ) VALUES (?, 'builtin', ?, NULL, NULL, ?)
          ''',
          <Object>[id, signifier.code, _now()],
        );
        ids[signifier] = id;
      }

      await _database.customStatement(
        'DELETE FROM entry_signifiers WHERE entry_id = ?',
        <Object>[entryId],
      );
      for (final JournalSignifier signifier in JournalSignifier.values) {
        final String? signifierId = ids[signifier];
        if (signifierId == null) {
          continue;
        }
        await _database.customStatement(
          '''
          INSERT INTO entry_signifiers (entry_id, signifier_id)
          VALUES (?, ?)
          ''',
          <Object>[entryId, signifierId],
        );
      }
    });
  }

  Future<String> migrateEntry({
    required String sourceEntryId,
    required JournalEntryOwner destinationOwner,
    required JournalMigrationKind kind,
  }) {
    return _database.transaction(() async {
      final _EntryRecord source = await _requireEntry(sourceEntryId);
      final _PlacementRecord sourcePlacement = await _requirePlacement(
        sourceEntryId,
      );

      final outgoing = await _database
          .customSelect(
            'SELECT 1 FROM migrations WHERE source_entry_id = ?',
            variables: <Variable<Object>>[Variable.withString(sourceEntryId)],
          )
          .getSingleOrNull();
      if (outgoing != null) {
        throw const JournalInvariantException(
          'An entry may have only one direct outgoing migration.',
        );
      }

      if (source.type == JournalEntryType.task &&
          source.taskState != JournalTaskState.open) {
        throw const JournalInvariantException(
          'Only an open task can be migrated or scheduled.',
        );
      }

      final _ResolvedOwner resolvedDestination = await _resolveOwner(
        destinationOwner,
      );
      if (_sameOwner(sourcePlacement, resolvedDestination)) {
        throw const JournalInvariantException(
          'Migration must move an entry to a different owner.',
        );
      }

      if (kind == JournalMigrationKind.scheduled &&
          resolvedDestination.logKind != JournalLogKind.future) {
        throw const JournalInvariantException(
          'Scheduled migration must target a Future Log.',
        );
      }
      if (kind == JournalMigrationKind.migrated &&
          resolvedDestination.logKind == JournalLogKind.future) {
        throw const JournalInvariantException(
          'A Future Log destination must use scheduled migration.',
        );
      }

      final int destinationOrdinal = await _nextPlacementOrdinal(
        resolvedDestination,
      );
      final int now = _now();
      final String destinationEntryId = _newId();
      final String migrationId = _newId();

      await _insertEntry(
        id: destinationEntryId,
        type: source.type,
        taskState: source.type == JournalEntryType.task
            ? JournalTaskState.open
            : null,
        content: source.content,
        now: now,
      );
      await _insertPlacement(
        entryId: destinationEntryId,
        owner: resolvedDestination,
        ordinal: destinationOrdinal,
      );
      await _database.customStatement(
        '''
        INSERT INTO entry_signifiers (entry_id, signifier_id)
        SELECT ?, signifier_id
        FROM entry_signifiers
        WHERE entry_id = ?
        ''',
        <Object>[destinationEntryId, sourceEntryId],
      );

      if (source.type == JournalEntryType.task) {
        await _database.customStatement(
          '''
          UPDATE entries
          SET task_state = ?, updated_at = ?
          WHERE id = ?
          ''',
          <Object>[kind.sourceTaskState.code, now, sourceEntryId],
        );
      }

      await _database.customStatement(
        '''
        INSERT INTO migrations (
          id, source_entry_id, destination_entry_id, kind, created_at
        ) VALUES (?, ?, ?, ?, ?)
        ''',
        <Object>[
          migrationId,
          sourceEntryId,
          destinationEntryId,
          kind.code,
          now,
        ],
      );

      return destinationEntryId;
    });
  }

  Future<_ResolvedOwner> _resolveOwner(JournalEntryOwner owner) async {
    switch (owner) {
      case JournalCollectionOwner(:final collectionId):
        await _requireCollection(collectionId);
        return _ResolvedOwner(collectionId: collectionId);
      case JournalLogOwner(
        :final logId,
        :final monthlySection,
        :final monthlyCalendarDate,
      ):
        final _LogRecord log = await _requireLog(logId);

        if (log.kind == JournalLogKind.monthly) {
          if (monthlySection == null) {
            throw const JournalInvariantException(
              'Monthly Log placements require a monthly section.',
            );
          }
          if (monthlySection == JournalMonthlySection.calendar) {
            if (monthlyCalendarDate == null) {
              throw const JournalInvariantException(
                'Monthly calendar placements require a calendar date.',
              );
            }
            _parseMethodDate(monthlyCalendarDate);
            if (!_sameMonth(log.periodStart, monthlyCalendarDate)) {
              throw JournalInvariantException(
                'Calendar date $monthlyCalendarDate is outside Monthly Log '
                '${log.periodStart}.',
              );
            }
          } else if (monthlyCalendarDate != null) {
            throw const JournalInvariantException(
              'Monthly task-list placements cannot have a calendar date.',
            );
          }
        } else if (monthlySection != null || monthlyCalendarDate != null) {
          throw const JournalInvariantException(
            'Daily and Future Log placements cannot use Monthly fields.',
          );
        }

        return _ResolvedOwner(
          logId: logId,
          logKind: log.kind,
          monthlySection: monthlySection,
          monthlyCalendarDate: monthlyCalendarDate,
        );
    }
  }

  Future<int> _nextPlacementOrdinal(_ResolvedOwner owner) async {
    final String clause;
    final String id;
    if (owner.logId != null) {
      clause = 'log_id = ?';
      id = owner.logId!;
    } else {
      clause = 'collection_id = ?';
      id = owner.collectionId!;
    }

    final row = await _database
        .customSelect(
          '''
      SELECT COALESCE(MAX(ordinal), -1) + 1 AS next_ordinal
      FROM entry_placements
      WHERE $clause
      ''',
          variables: <Variable<Object>>[Variable.withString(id)],
        )
        .getSingle();
    return row.read<int>('next_ordinal');
  }

  Future<void> _insertEntry({
    required String id,
    required JournalEntryType type,
    required JournalTaskState? taskState,
    required String content,
    required int now,
  }) {
    return _database.customStatement(
      '''
      INSERT INTO entries (
        id, entry_type, task_state, content, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[id, type.code, taskState?.code, content, now, now],
    );
  }

  Future<void> _insertPlacement({
    required String entryId,
    required _ResolvedOwner owner,
    required int ordinal,
  }) {
    return _database.customStatement(
      '''
      INSERT INTO entry_placements (
        entry_id,
        log_id,
        collection_id,
        ordinal,
        monthly_section,
        monthly_calendar_date
      ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        entryId,
        owner.logId,
        owner.collectionId,
        ordinal,
        owner.monthlySection?.code,
        owner.monthlyCalendarDate,
      ],
    );
  }

  Future<_EntryRecord> _requireEntry(String id) async {
    final row = await _database
        .customSelect(
          '''
      SELECT id, entry_type, task_state, content
      FROM entries
      WHERE id = ?
      ''',
          variables: <Variable<Object>>[Variable.withString(id)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw JournalNotFoundException('Entry', id);
    }

    return _EntryRecord(
      id: row.read<String>('id'),
      type: _entryTypeFromCode(row.read<String>('entry_type')),
      taskState: _taskStateFromCode(row.readNullable<String>('task_state')),
      content: row.read<String>('content'),
    );
  }

  Future<_PlacementRecord> _requirePlacement(String entryId) async {
    final row = await _database
        .customSelect(
          '''
      SELECT log_id, collection_id
      FROM entry_placements
      WHERE entry_id = ?
      ''',
          variables: <Variable<Object>>[Variable.withString(entryId)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw JournalInvariantException(
        'Entry $entryId does not have an owning placement.',
      );
    }
    return _PlacementRecord(
      logId: row.readNullable<String>('log_id'),
      collectionId: row.readNullable<String>('collection_id'),
    );
  }

  Future<_LogRecord> _requireLog(String id) async {
    final row = await _database
        .customSelect(
          'SELECT kind, period_start FROM logs WHERE id = ?',
          variables: <Variable<Object>>[Variable.withString(id)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw JournalNotFoundException('Log', id);
    }
    return _LogRecord(
      kind: _logKindFromCode(row.read<String>('kind')),
      periodStart: row.read<String>('period_start'),
    );
  }

  Future<void> _requireCollection(String id) async {
    final row = await _database
        .customSelect(
          'SELECT 1 FROM collections WHERE id = ?',
          variables: <Variable<Object>>[Variable.withString(id)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw JournalNotFoundException('Collection', id);
    }
  }

  String _newId() => _idGenerator().toLowerCase();

  int _now() {
    final int value = _nowUtcMicros();
    if (value < 0) {
      throw StateError('UTC microsecond clock returned a negative instant.');
    }
    return value;
  }
}

final class _ResolvedOwner {
  const _ResolvedOwner({
    this.logId,
    this.collectionId,
    this.logKind,
    this.monthlySection,
    this.monthlyCalendarDate,
  }) : assert((logId == null) != (collectionId == null));

  final String? logId;
  final String? collectionId;
  final JournalLogKind? logKind;
  final JournalMonthlySection? monthlySection;
  final String? monthlyCalendarDate;
}

final class _EntryRecord {
  const _EntryRecord({
    required this.id,
    required this.type,
    required this.taskState,
    required this.content,
  });

  final String id;
  final JournalEntryType type;
  final JournalTaskState? taskState;
  final String content;
}

final class _PlacementRecord {
  const _PlacementRecord({this.logId, this.collectionId});

  final String? logId;
  final String? collectionId;
}

final class _LogRecord {
  const _LogRecord({required this.kind, required this.periodStart});

  final JournalLogKind kind;
  final String periodStart;
}

bool _sameOwner(_PlacementRecord source, _ResolvedOwner destination) {
  if (source.logId != null) {
    return source.logId == destination.logId;
  }
  return source.collectionId == destination.collectionId;
}

void _validateLogPeriod(JournalLogKind kind, String periodStart) {
  final DateTime date = _parseMethodDate(periodStart);
  if ((kind == JournalLogKind.monthly || kind == JournalLogKind.future) &&
      date.day != 1) {
    throw const JournalInvariantException(
      'Monthly and Future Log periods must start on the first day of a month.',
    );
  }
}

DateTime _parseMethodDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw JournalInvariantException('Invalid method date: $value.');
  }
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null ||
      '${parsed.year.toString().padLeft(4, '0')}-'
              '${parsed.month.toString().padLeft(2, '0')}-'
              '${parsed.day.toString().padLeft(2, '0')}' !=
          value) {
    throw JournalInvariantException('Invalid method date: $value.');
  }
  return parsed;
}

bool _sameMonth(String periodStart, String calendarDate) {
  return periodStart.substring(0, 7) == calendarDate.substring(0, 7);
}

JournalLogKind _logKindFromCode(String code) => switch (code) {
  'daily' => JournalLogKind.daily,
  'monthly' => JournalLogKind.monthly,
  'future' => JournalLogKind.future,
  _ => throw JournalInvariantException('Unknown persisted log kind: $code.'),
};

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

String _defaultIdGenerator() => const Uuid().v7();

int _defaultNowUtcMicros() => DateTime.now().toUtc().microsecondsSinceEpoch;
