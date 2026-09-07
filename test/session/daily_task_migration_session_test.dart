import 'dart:io';

import 'package:daymark/core/crypto/key_envelope.dart';
import 'package:daymark/core/session/journal_files.dart';
import 'package:daymark/core/session/journal_session.dart';
import 'package:daymark/features/journal/data/daily_log_repository.dart';
import 'package:daymark/features/journal/data/future_log_repository.dart';
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

  test(
    'Daily Task migration rejects same-day and backward destinations',
    () async {
      final JournalSession session = await manager.create(
        masterPassword: 'forward daily migration journal',
      );
      final DailyLogSnapshot source = await session.loadDailyLog('2026-09-07');
      await session.captureDailyLogEntry(
        logId: source.logId,
        type: JournalEntryType.task,
        content: 'Only move forward',
      );
      final String entryId = (await session.loadDailyLog('2026-09-07'))
          .entries
          .single
          .id;

      await expectLater(
        session.migrateTaskToDaily(entryId: entryId, methodDate: '2026-09-07'),
        throwsA(isA<JournalInvariantException>()),
      );
      await expectLater(
        session.migrateTaskToDaily(entryId: entryId, methodDate: '2026-09-06'),
        throwsA(isA<JournalInvariantException>()),
      );

      expect(
        (await session.loadDailyLog('2026-09-07')).entries.single.taskState,
        JournalTaskState.open,
      );
      final earlierDestinationCount = await session.database.customSelect('''
          SELECT COUNT(*) AS count
          FROM logs
          WHERE kind = 'daily' AND period_start = '2026-09-06'
          ''').getSingle();
      expect(earlierDestinationCount.read<int>('count'), 0);
    },
  );

  test('Monthly Task can migrate into the next Monthly Tasks list', () async {
    final JournalSession session = await manager.create(
      masterPassword: 'monthly carry journal',
    );
    final MonthlyLogSnapshot september = await session.loadMonthlyLog(
      '2026-09-01',
    );
    await session.captureMonthlyTask(
      logId: september.logId,
      content: 'Carry into October',
    );
    final String sourceEntryId = (await session.loadMonthlyLog('2026-09-01'))
        .taskEntries
        .single
        .id;

    await session.migrateTaskToMonthlyTasks(
      entryId: sourceEntryId,
      periodStart: '2026-10-01',
    );

    final MonthlyLogSnapshot sourceAfter = await session.loadMonthlyLog(
      '2026-09-01',
    );
    final MonthlyLogSnapshot destination = await session.loadMonthlyLog(
      '2026-10-01',
    );
    expect(sourceAfter.taskEntries.single.taskState, JournalTaskState.migrated);
    expect(destination.taskEntries.single.id, isNot(sourceEntryId));
    expect(destination.taskEntries.single.content, 'Carry into October');
    expect(destination.taskEntries.single.taskState, JournalTaskState.open);
  });

  test('arrived Future Task migrates into matching Monthly Tasks with lineage chain', () async {
    final JournalSession session = await manager.create(
      masterPassword: 'future arrival journal',
    );
    final DailyLogSnapshot daily = await session.loadDailyLog('2026-09-07');
    await session.captureDailyLogEntry(
      logId: daily.logId,
      type: JournalEntryType.task,
      content: 'Renew October permit',
    );
    final String originalEntryId = (await session.loadDailyLog('2026-09-07'))
        .entries
        .single
        .id;

    await session.scheduleTaskToFuture(
      entryId: originalEntryId,
      periodStart: '2026-10-01',
    );
    final FutureLogSnapshot future = await session.loadFutureLog('2026-10-01');
    final String futureEntryId = future.entries.single.id;

    await session.migrateTaskToMonthlyTasks(
      entryId: futureEntryId,
      periodStart: '2026-10-01',
    );

    final DailyLogSnapshot originalAfter = await session.loadDailyLog(
      '2026-09-07',
    );
    final FutureLogSnapshot futureAfter = await session.loadFutureLog(
      '2026-10-01',
    );
    final MonthlyLogSnapshot monthlyAfter = await session.loadMonthlyLog(
      '2026-10-01',
    );
    expect(originalAfter.entries.single.taskState, JournalTaskState.scheduled);
    expect(futureAfter.entries.single.taskState, JournalTaskState.migrated);
    expect(monthlyAfter.taskEntries.single.content, 'Renew October permit');
    expect(monthlyAfter.taskEntries.single.taskState, JournalTaskState.open);

    final migrations = await session.database.customSelect('''
          SELECT source_entry_id, destination_entry_id, kind
          FROM migrations
          ORDER BY created_at, source_entry_id
          ''').get();
    expect(migrations, hasLength(2));
    final scheduled = migrations.singleWhere(
      (row) => row.read<String>('source_entry_id') == originalEntryId,
    );
    final migrated = migrations.singleWhere(
      (row) => row.read<String>('source_entry_id') == futureEntryId,
    );
    expect(scheduled.read<String>('kind'), 'scheduled');
    expect(scheduled.read<String>('destination_entry_id'), futureEntryId);
    expect(migrated.read<String>('kind'), 'migrated');
    expect(
      migrated.read<String>('destination_entry_id'),
      monthlyAfter.taskEntries.single.id,
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

  test('Monthly Calendar accepts a dated Task', () async {
    final JournalSession session = await manager.create(
      masterPassword: 'dated monthly task journal',
    );
    final MonthlyLogSnapshot monthly = await session.loadMonthlyLog(
      '2026-09-01',
    );
    await session.captureMonthlyCalendarTask(
      logId: monthly.logId,
      calendarDate: '2026-09-15',
      content: 'Submit dated report',
    );

    final MonthlyLogSnapshot reloaded = await session.loadMonthlyLog(
      '2026-09-01',
    );
    final MonthlyLogEntry entry = reloaded.calendarEntries.singleWhere(
      (item) => item.content == 'Submit dated report',
    );
    expect(entry.type, JournalEntryType.task);
    expect(entry.taskState, JournalTaskState.open);
    expect(entry.calendarDate, '2026-09-15');

    await session.completeTask(entryId: entry.id);
    expect(
      (await session.loadMonthlyLog('2026-09-01'))
          .calendarEntries
          .single
          .taskState,
      JournalTaskState.completed,
    );
  });

  test(
    'Future Event migrates into a chosen day in matching Monthly Calendar',
    () async {
      final JournalSession session = await manager.create(
        masterPassword: 'future event arrival journal',
      );
      final FutureLogSnapshot future = await session.loadFutureLog(
        '2026-09-01',
      );
      await session.captureFutureLogEntry(
        logId: future.logId,
        type: JournalEntryType.event,
        content: 'Dentist appointment',
      );
      final String sourceEntryId = (await session.loadFutureLog('2026-09-01'))
          .entries
          .single
          .id;

      await session.migrateFutureEventToMonthlyCalendar(
        entryId: sourceEntryId,
        periodStart: '2026-09-01',
        calendarDate: '2026-09-17',
      );

      final FutureLogSnapshot sourceAfter = await session.loadFutureLog(
        '2026-09-01',
      );
      expect(sourceAfter.entries.single.id, sourceEntryId);
      expect(sourceAfter.entries.single.type, JournalEntryType.event);
      expect(sourceAfter.entries.single.hasOutgoingMigration, isTrue);

      final MonthlyLogSnapshot monthly = await session.loadMonthlyLog(
        '2026-09-01',
      );
      final MonthlyLogEntry destination = monthly.calendarEntries.singleWhere(
        (entry) => entry.content == 'Dentist appointment',
      );
      expect(destination.id, isNot(sourceEntryId));
      expect(destination.type, JournalEntryType.event);
      expect(destination.calendarDate, '2026-09-17');

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
      expect(
        migration.read<String>('kind'),
        JournalMigrationKind.migrated.code,
      );
      expect(migration.read<String>('destination_entry_id'), destination.id);
    },
  );

  test(
    'Future Event migration rejects a day outside its Future month',
    () async {
      final JournalSession session = await manager.create(
        masterPassword: 'future event month validation journal',
      );
      final FutureLogSnapshot future = await session.loadFutureLog(
        '2026-09-01',
      );
      await session.captureFutureLogEntry(
        logId: future.logId,
        type: JournalEntryType.event,
        content: 'Conference',
      );
      final String sourceEntryId = (await session.loadFutureLog('2026-09-01'))
          .entries
          .single
          .id;

      await expectLater(
        session.migrateFutureEventToMonthlyCalendar(
          entryId: sourceEntryId,
          periodStart: '2026-09-01',
          calendarDate: '2026-10-01',
        ),
        throwsA(isA<JournalInvariantException>()),
      );
      final monthlyDestinationCount = await session.database.customSelect('''
          SELECT COUNT(*) AS count
          FROM logs
          WHERE kind = 'monthly' AND period_start = '2026-09-01'
          ''').getSingle();
      expect(monthlyDestinationCount.read<int>('count'), 0);
      expect(
        (await session.loadFutureLog('2026-09-01'))
            .entries
            .single
            .hasOutgoingMigration,
        isFalse,
      );
    },
  );

  test('Signifiers persist and follow deliberate migration', () async {
    final JournalSession session = await manager.create(
      masterPassword: 'signifier migration journal',
    );
    final DailyLogSnapshot source = await session.loadDailyLog('2026-09-07');
    await session.captureDailyLogEntry(
      logId: source.logId,
      type: JournalEntryType.task,
      content: 'Read architecture notes',
    );
    final String sourceEntryId = (await session.loadDailyLog('2026-09-07'))
        .entries
        .single
        .id;

    await session.replaceEntrySignifiers(
      entryId: sourceEntryId,
      signifiers: const <JournalSignifier>{
        JournalSignifier.priority,
        JournalSignifier.explore,
      },
    );
    expect(
      await session.listEntrySignifiers(entryId: sourceEntryId),
      const <JournalSignifier>{
        JournalSignifier.priority,
        JournalSignifier.explore,
      },
    );

    await session.migrateTaskToDaily(
      entryId: sourceEntryId,
      methodDate: '2026-09-08',
    );
    final String destinationEntryId = (await session.loadDailyLog('2026-09-08'))
        .entries
        .single
        .id;

    expect(
      await session.listEntrySignifiers(entryId: destinationEntryId),
      const <JournalSignifier>{
        JournalSignifier.priority,
        JournalSignifier.explore,
      },
    );
    expect(
      await session.listEntrySignifiers(entryId: sourceEntryId),
      const <JournalSignifier>{
        JournalSignifier.priority,
        JournalSignifier.explore,
      },
    );
  });
}
