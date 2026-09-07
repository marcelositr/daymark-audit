from pathlib import Path

path = Path("test/session/daily_task_migration_session_test.dart")
text = path.read_text()
if "Monthly Calendar accepts a dated Task" not in text:
    insertion = r"""

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

  test('Future Event migrates into a chosen day in matching Monthly Calendar', () async {
    final JournalSession session = await manager.create(
      masterPassword: 'future event arrival journal',
    );
    final FutureLogSnapshot future = await session.loadFutureLog('2026-09-01');
    await session.captureFutureLogEntry(
      logId: future.logId,
      type: JournalEntryType.event,
      content: 'Dentist appointment',
    );
    final String sourceEntryId =
        (await session.loadFutureLog('2026-09-01')).entries.single.id;

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
    expect(migration.read<String>('kind'), JournalMigrationKind.migrated.code);
    expect(migration.read<String>('destination_entry_id'), destination.id);
  });

  test('Future Event migration rejects a day outside its Future month', () async {
    final JournalSession session = await manager.create(
      masterPassword: 'future event month validation journal',
    );
    final FutureLogSnapshot future = await session.loadFutureLog('2026-09-01');
    await session.captureFutureLogEntry(
      logId: future.logId,
      type: JournalEntryType.event,
      content: 'Conference',
    );
    final String sourceEntryId =
        (await session.loadFutureLog('2026-09-01')).entries.single.id;

    await expectLater(
      session.migrateFutureEventToMonthlyCalendar(
        entryId: sourceEntryId,
        periodStart: '2026-09-01',
        calendarDate: '2026-10-01',
      ),
      throwsA(isA<JournalInvariantException>()),
    );
    expect(await session.findMonthlyLog('2026-09-01'), isNull);
    expect(
      (await session.loadFutureLog('2026-09-01'))
          .entries
          .single
          .hasOutgoingMigration,
      isFalse,
    );
  });

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
    final String sourceEntryId =
        (await session.loadDailyLog('2026-09-07')).entries.single.id;

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
    final String destinationEntryId =
        (await session.loadDailyLog('2026-09-08')).entries.single.id;

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
"""
    end = text.rfind('\n}')
    if end < 0:
        raise SystemExit('main test group closing brace not found')
    path.write_text(text[:end] + insertion + text[end:])

print("fidelity tests staged")