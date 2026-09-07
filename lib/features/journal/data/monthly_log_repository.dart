import 'package:daymark/core/database/daymark_database.dart';
import 'package:daymark/features/journal/application/journal_service.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:drift/drift.dart';

final class MonthlyLogEntry {
  const MonthlyLogEntry({
    required this.id,
    required this.type,
    required this.taskState,
    required this.content,
    required this.ordinal,
    required this.section,
    required this.calendarDate,
  });

  final String id;
  final JournalEntryType type;
  final JournalTaskState? taskState;
  final String content;
  final int ordinal;
  final JournalMonthlySection section;
  final String? calendarDate;
}

final class MonthlyLogSnapshot {
  MonthlyLogSnapshot({
    required this.logId,
    required this.periodStart,
    required List<MonthlyLogEntry> calendarEntries,
    required List<MonthlyLogEntry> taskEntries,
  }) : calendarEntries = List<MonthlyLogEntry>.unmodifiable(calendarEntries),
       taskEntries = List<MonthlyLogEntry>.unmodifiable(taskEntries);

  final String logId;
  final String periodStart;
  final List<MonthlyLogEntry> calendarEntries;
  final List<MonthlyLogEntry> taskEntries;
}

/// Focused read/write boundary for one Monthly Log.
///
/// Reads query encrypted storage directly. Mutations continue through the
/// semantic [JournalService], which owns Monthly placement invariants.
final class MonthlyLogRepository {
  const MonthlyLogRepository(this._database, this._journalService);

  final DaymarkDatabase _database;
  final JournalService _journalService;

  Future<MonthlyLogSnapshot?> find(String periodStart) async {
    validateJournalMonthStart(periodStart);
    final String? logId = await _findMonthlyLogId(periodStart);
    if (logId == null) {
      return null;
    }
    return _loadSnapshot(logId: logId, periodStart: periodStart);
  }

  Future<MonthlyLogSnapshot> loadOrCreate(String periodStart) async {
    validateJournalMonthStart(periodStart);

    String? logId = await _findMonthlyLogId(periodStart);
    if (logId == null) {
      try {
        logId = await _journalService.createLog(
          kind: JournalLogKind.monthly,
          periodStart: periodStart,
        );
      } on JournalInvariantException {
        logId = await _findMonthlyLogId(periodStart);
        if (logId == null) {
          rethrow;
        }
      }
    }

    return _loadSnapshot(logId: logId, periodStart: periodStart);
  }

  Future<void> captureCalendarEvent({
    required String logId,
    required String calendarDate,
    required String content,
  }) {
    return _journalService.capture(
      type: JournalEntryType.event,
      content: content,
      owner: JournalLogOwner(
        logId: logId,
        monthlySection: JournalMonthlySection.calendar,
        monthlyCalendarDate: calendarDate,
      ),
    );
  }

  Future<void> captureCalendarTask({
    required String logId,
    required String calendarDate,
    required String content,
  }) {
    return _journalService.capture(
      type: JournalEntryType.task,
      content: content,
      owner: JournalLogOwner(
        logId: logId,
        monthlySection: JournalMonthlySection.calendar,
        monthlyCalendarDate: calendarDate,
      ),
    );
  }

  Future<void> captureTask({required String logId, required String content}) {
    return _journalService.capture(
      type: JournalEntryType.task,
      content: content,
      owner: JournalLogOwner(
        logId: logId,
        monthlySection: JournalMonthlySection.tasks,
      ),
    );
  }

  Future<MonthlyLogSnapshot> _loadSnapshot({
    required String logId,
    required String periodStart,
  }) async {
    final List<MonthlyLogEntry> entries = await _loadEntries(logId);
    return MonthlyLogSnapshot(
      logId: logId,
      periodStart: periodStart,
      calendarEntries: <MonthlyLogEntry>[
        for (final MonthlyLogEntry entry in entries)
          if (entry.section == JournalMonthlySection.calendar) entry,
      ],
      taskEntries: <MonthlyLogEntry>[
        for (final MonthlyLogEntry entry in entries)
          if (entry.section == JournalMonthlySection.tasks) entry,
      ],
    );
  }

  Future<String?> _findMonthlyLogId(String periodStart) async {
    final row = await _database
        .customSelect(
          '''
          SELECT id
          FROM logs
          WHERE kind = 'monthly' AND period_start = ?
          ''',
          variables: <Variable<Object>>[Variable.withString(periodStart)],
        )
        .getSingleOrNull();
    return row?.read<String>('id');
  }

  Future<List<MonthlyLogEntry>> _loadEntries(String logId) async {
    final rows = await _database
        .customSelect(
          '''
          SELECT
            e.id,
            e.entry_type,
            e.task_state,
            e.content,
            p.ordinal,
            p.monthly_section,
            p.monthly_calendar_date
          FROM entry_placements p
          JOIN entries e ON e.id = p.entry_id
          WHERE p.log_id = ?
          ORDER BY p.ordinal
          ''',
          variables: <Variable<Object>>[Variable.withString(logId)],
        )
        .get();

    return <MonthlyLogEntry>[
      for (final row in rows)
        MonthlyLogEntry(
          id: row.read<String>('id'),
          type: _entryTypeFromCode(row.read<String>('entry_type')),
          taskState: _taskStateFromCode(row.readNullable<String>('task_state')),
          content: row.read<String>('content'),
          ordinal: row.read<int>('ordinal'),
          section: _monthlySectionFromCode(row.read<String>('monthly_section')),
          calendarDate: row.readNullable<String>('monthly_calendar_date'),
        ),
    ];
  }
}

String formatJournalMonthStart(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-01';
}

void validateJournalMonthStart(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-01$').hasMatch(value)) {
    throw JournalInvariantException('Invalid Monthly Log period: $value.');
  }
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null || formatJournalMonthStart(parsed) != value) {
    throw JournalInvariantException('Invalid Monthly Log period: $value.');
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

JournalMonthlySection _monthlySectionFromCode(String code) => switch (code) {
  'calendar' => JournalMonthlySection.calendar,
  'tasks' => JournalMonthlySection.tasks,
  _ => throw JournalInvariantException(
    'Unknown persisted Monthly Log section: $code.',
  ),
};
