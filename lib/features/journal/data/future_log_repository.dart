import 'package:daymark/core/database/daymark_database.dart';
import 'package:daymark/features/journal/application/journal_service.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:drift/drift.dart';

final class FutureLogEntry {
  const FutureLogEntry({
    required this.id,
    required this.type,
    required this.taskState,
    required this.content,
    required this.ordinal,
    this.hasOutgoingMigration = false,
  });

  final String id;
  final JournalEntryType type;
  final JournalTaskState? taskState;
  final String content;
  final int ordinal;
  final bool hasOutgoingMigration;
}

final class FutureLogSnapshot {
  FutureLogSnapshot({
    required this.logId,
    required this.periodStart,
    required List<FutureLogEntry> entries,
  }) : entries = List<FutureLogEntry>.unmodifiable(entries);

  final String logId;
  final String periodStart;
  final List<FutureLogEntry> entries;
}

/// Focused read/write boundary for one Future Log month bucket.
///
/// Reads query encrypted storage directly. Mutations continue through the
/// semantic [JournalService], while this boundary verifies the supplied owner
/// really is a Future Log before capture.
final class FutureLogRepository {
  const FutureLogRepository(this._database, this._journalService);

  final DaymarkDatabase _database;
  final JournalService _journalService;

  Future<FutureLogSnapshot> loadOrCreate(String periodStart) async {
    validateFuturePeriodStart(periodStart);

    String? logId = await _findFutureLogId(periodStart);
    if (logId == null) {
      try {
        logId = await _journalService.createLog(
          kind: JournalLogKind.future,
          periodStart: periodStart,
        );
      } on JournalInvariantException {
        logId = await _findFutureLogId(periodStart);
        if (logId == null) {
          rethrow;
        }
      }
    }

    return FutureLogSnapshot(
      logId: logId,
      periodStart: periodStart,
      entries: await _loadEntries(logId),
    );
  }

  Future<FutureLogSnapshot?> find(String periodStart) async {
    validateFuturePeriodStart(periodStart);

    final String? logId = await _findFutureLogId(periodStart);
    if (logId == null) {
      return null;
    }

    return FutureLogSnapshot(
      logId: logId,
      periodStart: periodStart,
      entries: await _loadEntries(logId),
    );
  }

  Future<void> capture({
    required String logId,
    required JournalEntryType type,
    required String content,
  }) async {
    await _requireFutureLog(logId);
    await _journalService.capture(
      type: type,
      content: content,
      owner: JournalLogOwner(logId: logId),
    );
  }

  Future<String?> _findFutureLogId(String periodStart) async {
    final row = await _database
        .customSelect(
          '''
          SELECT id
          FROM logs
          WHERE kind = 'future' AND period_start = ?
          ''',
          variables: <Variable<Object>>[Variable.withString(periodStart)],
        )
        .getSingleOrNull();
    return row?.read<String>('id');
  }

  Future<void> _requireFutureLog(String logId) async {
    final row = await _database
        .customSelect(
          'SELECT kind FROM logs WHERE id = ?',
          variables: <Variable<Object>>[Variable.withString(logId)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw JournalNotFoundException('Log', logId);
    }
    if (row.read<String>('kind') != JournalLogKind.future.code) {
      throw const JournalInvariantException(
        'Future Log capture requires a Future Log owner.',
      );
    }
  }

  Future<List<FutureLogEntry>> _loadEntries(String logId) async {
    final rows = await _database
        .customSelect(
          '''
          SELECT
            e.id,
            e.entry_type,
            e.task_state,
            e.content,
            p.ordinal,
            CASE WHEN m.source_entry_id IS NULL THEN 0 ELSE 1 END
              AS has_outgoing_migration
          FROM entry_placements p
          JOIN entries e ON e.id = p.entry_id
          LEFT JOIN migrations m ON m.source_entry_id = e.id
          WHERE p.log_id = ?
          ORDER BY p.ordinal
          ''',
          variables: <Variable<Object>>[Variable.withString(logId)],
        )
        .get();

    return <FutureLogEntry>[
      for (final row in rows)
        FutureLogEntry(
          id: row.read<String>('id'),
          type: _entryTypeFromCode(row.read<String>('entry_type')),
          taskState: _taskStateFromCode(row.readNullable<String>('task_state')),
          content: row.read<String>('content'),
          ordinal: row.read<int>('ordinal'),
          hasOutgoingMigration: row.read<int>('has_outgoing_migration') != 0,
        ),
    ];
  }
}

String formatFuturePeriodStart(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-01';
}

void validateFuturePeriodStart(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-01$').hasMatch(value)) {
    throw JournalInvariantException('Invalid Future Log period: $value.');
  }
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null || formatFuturePeriodStart(parsed) != value) {
    throw JournalInvariantException('Invalid Future Log period: $value.');
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
