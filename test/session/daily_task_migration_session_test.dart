import 'dart:io';

import 'package:daymark/core/crypto/key_envelope.dart';
import 'package:daymark/core/session/journal_files.dart';
import 'package:daymark/core/session/journal_session.dart';
import 'package:daymark/features/journal/data/daily_log_repository.dart';
import 'package:daymark/features/journal/data/monthly_log_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late JournalFiles files;
  late JournalSessionManager manager;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'daymark-daily-task-migration-session-test-',
    );
    files = JournalFiles(directory);
    manager = JournalSessionManager(
      files: files,
      keyEnvelopeService: KeyEnvelopeService(parameters: Argon2Parameters.test),
    );
  });

  tearDown(() async {
    await manager.dispose();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('Daily Task migration preserves source, destination, lineage and unlock persistence', () async {
    final JournalSession created = await manager.create(
      masterPassword: 'daily migration journal',
    );

    final DailyLogSnapshot sourceLog = await created.loadDailyLog('2026-09-07');
    await created.captureDailyLogEntry(
      logId: sourceLog.logId,
      type: JournalEntryType.task,
      content: 'Carry this forward',
    );

    final String sourceEntryId = (await created.loadDailyLog('2026-09-07'))
        .entries
        .single
        .id;

    await created.migrateTaskToDaily(
      entryId: sourceEntryId,
      methodDate: '2026-09-08',
    );

    final DailyLogSnapshot migratedSource = await created.loadDailyLog(
      '2026-09-07',
    );
    final DailyLogSnapshot destination = await created.loadDailyLog(
      '2026-09-08',
    );

    expect(migratedSource.entries, hasLength(1));
    expect(migratedSource.entries.single.id, sourceEntryId);
    expect(migratedSource.entries.single.content, 'Carry this forward');
    expect(migratedSource.entries.single.taskState, JournalTaskState.migrated);

    expect(destination.entries, hasLength(1));
    expect(destination.entries.single.id, isNot(sourceEntryId));
    expect(destination.entries.single.content, 'Carry this forward');
    expect(destination.entries.single.taskState, JournalTaskState.open);

    final migration = await created.database
        .customSelect(
          '''
            SELECT destination_entry_id, kind
            FROM migrations
            WHERE source_entry_id = ?
            ''',
          variables: <Variable<Object>>[Variable.withString(sourceEntryId)],
        )
        .getSingle();
    expect(migration.read<String>('kind'), 'migrated');
    expect(
      migration.read<String>('destination_entry_id'),
      destination.entries.single.id,
    );

    await manager.lock();
    final JournalSession reopened = await manager.unlock(
      masterPassword: 'daily migration journal',
    );

    final DailyLogSnapshot reopenedSource = await reopened.loadDailyLog(
      '2026-09-07',
    );
    final DailyLogSnapshot reopenedDestination = await reopened.loadDailyLog(
      '2026-09-08',
    );

    expect(reopenedSource.entries.single.taskState, JournalTaskState.migrated);
    expect(reopenedDestination.entries.single.content, 'Carry this forward');
    expect(reopenedDestination.entries.single.taskState, JournalTaskState.open);
  });

  test('Monthly Task can migrate into a Daily Log with lineage', () async {
    final JournalSession session = await manager.create(
      masterPassword: 'monthly to daily migration journal',
    );
    final MonthlyLogSnapshot monthly = await session.loadMonthlyLog(
      '2026-09-01',
    );
    await session.captureMonthlyTask(
      logId: monthly.logId,
      content: 'Carry monthly task forward',
    );

    final String sourceEntryId = (await session.loadMonthlyLog('2026-09-01'))
        .taskEntries
        .single
        .id;

    await session.migrateTaskToDaily(
      entryId: sourceEntryId,
      methodDate: '2026-09-08',
    );

    final MonthlyLogSnapshot sourceAfter = await session.loadMonthlyLog(
      '2026-09-01',
    );
    final DailyLogSnapshot destination = await session.loadDailyLog(
      '2026-09-08',
    );

    expect(sourceAfter.taskEntries.single.id, sourceEntryId);
    expect(sourceAfter.taskEntries.single.taskState, JournalTaskState.migrated);
    expect(destination.entries, hasLength(1));
    expect(destination.entries.single.id, isNot(sourceEntryId));
    expect(destination.entries.single.content, 'Carry monthly task forward');
    expect(destination.entries.single.taskState, JournalTaskState.open);

    final migration = await session.database
        .customSelect(
          '''
          SELECT destination_entry_id, kind
          FROM migrations
          WHERE source_entry_id = ?
          ''',
          variables: <Variable<Object>>[Variable.withString(sourceEntryId)],
        )
        .getSingle();
    expect(migration.read<String>('kind'), 'migrated');
    expect(
      migration.read<String>('destination_entry_id'),
      destination.entries.single.id,
    );
  });

  test('invalid source does not create a destination Daily Log', () async {
    final JournalSession session = await manager.create(
      masterPassword: 'daily migration validation journal',
    );
    final DailyLogSnapshot source = await session.loadDailyLog('2026-09-07');

    await session.captureDailyLogEntry(
      logId: source.logId,
      type: JournalEntryType.event,
      content: 'Not a Task',
    );
    await session.captureDailyLogEntry(
      logId: source.logId,
      type: JournalEntryType.task,
      content: 'Already complete',
    );

    final DailyLogSnapshot captured = await session.loadDailyLog('2026-09-07');
    final String eventId = captured.entries
        .singleWhere((entry) => entry.content == 'Not a Task')
        .id;
    final String completedTaskId = captured.entries
        .singleWhere((entry) => entry.content == 'Already complete')
        .id;
    await session.completeTask(entryId: completedTaskId);

    expect(
      () => session.migrateTaskToDaily(
        entryId: eventId,
        methodDate: '2026-09-08',
      ),
      throwsA(isA<JournalInvariantException>()),
    );
    expect(
      () => session.migrateTaskToDaily(
        entryId: completedTaskId,
        methodDate: '2026-09-08',
      ),
      throwsA(isA<JournalInvariantException>()),
    );

    final destinationCount = await session.database.customSelect('''
          SELECT COUNT(*) AS count
          FROM logs
          WHERE kind = 'daily' AND period_start = '2026-09-08'
          ''').getSingle();
    expect(destinationCount.read<int>('count'), 0);
  });
}
