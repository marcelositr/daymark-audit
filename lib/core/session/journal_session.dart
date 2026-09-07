import 'dart:async';
import 'dart:io';

import 'package:daymark/core/backup/encrypted_backup_service.dart';
import 'package:daymark/core/crypto/journal_key_material.dart';
import 'package:daymark/core/crypto/key_envelope.dart';
import 'package:daymark/core/crypto/security_exception.dart';
import 'package:daymark/core/database/daymark_database.dart';
import 'package:daymark/core/database/encrypted_daymark_database.dart';
import 'package:daymark/features/journal/application/journal_service.dart';
import 'package:daymark/features/journal/application/task_action_service.dart';
import 'package:daymark/features/journal/data/collection_repository.dart';
import 'package:daymark/features/journal/data/daily_log_repository.dart';
import 'package:daymark/features/journal/data/future_log_repository.dart';
import 'package:daymark/features/journal/data/journal_repository.dart';
import 'package:daymark/features/journal/data/monthly_log_repository.dart';
import 'package:daymark/features/journal/data/task_action_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'journal_files.dart';

sealed class JournalAccessState {
  const JournalAccessState();
}

final class JournalNeedsCreation extends JournalAccessState {
  const JournalNeedsCreation();
}

final class JournalLocked extends JournalAccessState {
  const JournalLocked();
}

final class JournalStorageProblem extends JournalAccessState {
  const JournalStorageProblem();
}

final class JournalUnlocked extends JournalAccessState {
  const JournalUnlocked(this.session);

  final JournalSession session;
}

/// Owns every object that is valid only while one journal is unlocked.
///
/// Journal operations are serialized here. Once closing begins no new
/// operation can enter the database, and [close] waits for the current queued
/// work before closing encrypted persistence and destroying key material.
final class JournalSession {
  JournalSession._(this.database, this._keyMaterial)
    : repository = JournalRepository(database) {
    service = JournalService(repository);
    taskActions = TaskActionService(TaskActionRepository(database));
    collections = CollectionRepository(database, service);
    dailyLog = DailyLogRepository(database, service);
    monthlyLog = MonthlyLogRepository(database, service);
    futureLog = FutureLogRepository(database, service);
  }

  final DaymarkDatabase database;
  final JournalKeyMaterial _keyMaterial;
  final JournalRepository repository;
  late final JournalService service;
  late final TaskActionService taskActions;
  late final CollectionRepository collections;
  late final DailyLogRepository dailyLog;
  late final MonthlyLogRepository monthlyLog;
  late final FutureLogRepository futureLog;

  Future<void> _operationTail = Future<void>.value();
  bool _closing = false;
  bool _closed = false;

  bool get isClosed => _closed;

  Future<T> run<T>(Future<T> Function() operation) {
    if (_closing || _closed) {
      return Future<T>.error(
        StateError('The journal session is closing or already closed.'),
      );
    }

    final Completer<T> completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      if (_closing || _closed) {
        completer.completeError(
          StateError('The journal session is closing or already closed.'),
        );
        return;
      }

      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<DailyLogSnapshot> loadDailyLog(String methodDate) {
    return run(() => dailyLog.loadOrCreate(methodDate));
  }

  Future<void> captureDailyLogEntry({
    required String logId,
    required JournalEntryType type,
    required String content,
  }) {
    return run(
      () => dailyLog.capture(logId: logId, type: type, content: content),
    );
  }

  Future<MonthlyLogSnapshot> loadMonthlyLog(String periodStart) {
    return run(() => monthlyLog.loadOrCreate(periodStart));
  }

  Future<void> captureMonthlyCalendarEvent({
    required String logId,
    required String calendarDate,
    required String content,
  }) {
    return run(
      () => monthlyLog.captureCalendarEvent(
        logId: logId,
        calendarDate: calendarDate,
        content: content,
      ),
    );
  }

  Future<void> captureMonthlyCalendarTask({
    required String logId,
    required String calendarDate,
    required String content,
  }) {
    return run(
      () => monthlyLog.captureCalendarTask(
        logId: logId,
        calendarDate: calendarDate,
        content: content,
      ),
    );
  }

  Future<void> captureMonthlyTask({
    required String logId,
    required String content,
  }) {
    return run(() => monthlyLog.captureTask(logId: logId, content: content));
  }

  Future<FutureLogSnapshot> loadFutureLog(String periodStart) {
    return run(() => futureLog.loadOrCreate(periodStart));
  }

  Future<void> captureFutureLogEntry({
    required String logId,
    required JournalEntryType type,
    required String content,
  }) {
    return run(
      () => futureLog.capture(logId: logId, type: type, content: content),
    );
  }

  Future<List<CollectionSummary>> listCollections() {
    return run(collections.list);
  }

  Future<String> createCollection({required String title}) {
    return run(() => collections.create(title: title));
  }

  Future<void> undoCollectionCreation({required String collectionId}) {
    return run(() => collections.undoCreate(collectionId));
  }

  Future<CollectionSnapshot> loadCollection(String collectionId) {
    return run(() => collections.load(collectionId));
  }

  Future<void> captureCollectionEntry({
    required String collectionId,
    required JournalEntryType type,
    required String content,
  }) {
    return run(
      () => collections.capture(
        collectionId: collectionId,
        type: type,
        content: content,
      ),
    );
  }

  Future<void> undoCapture({required String entryId}) {
    return run(() => service.undoCapture(entryId: entryId));
  }

  Future<void> referenceEntryInCollection({
    required String entryId,
    required String collectionId,
  }) {
    return run(
      () => collections.reference(collectionId: collectionId, entryId: entryId),
    );
  }

  Future<void> removeEntryReferenceFromCollection({
    required String entryId,
    required String collectionId,
  }) {
    return run(
      () => collections.removeReference(
        collectionId: collectionId,
        entryId: entryId,
      ),
    );
  }

  Future<Set<JournalSignifier>> listEntrySignifiers({required String entryId}) {
    return run(() => service.listEntrySignifiers(entryId: entryId));
  }

  Future<void> replaceEntrySignifiers({
    required String entryId,
    required Set<JournalSignifier> signifiers,
  }) {
    return run(
      () => service.replaceEntrySignifiers(
        entryId: entryId,
        signifiers: signifiers,
      ),
    );
  }

  Future<void> migrateTaskToDaily({
    required String entryId,
    required String methodDate,
  }) {
    return run(() async {
      validateJournalMethodDate(methodDate);
      await taskActions.requireOpen(entryId: entryId);
      await _requireForwardDailyDestination(
        entryId: entryId,
        methodDate: methodDate,
      );
      final DailyLogSnapshot destination = await dailyLog.loadOrCreate(
        methodDate,
      );
      await service.migrate(
        sourceEntryId: entryId,
        destinationOwner: JournalLogOwner(logId: destination.logId),
      );
    });
  }

  Future<void> migrateTaskToMonthlyTasks({
    required String entryId,
    required String periodStart,
  }) {
    return run(() async {
      validateJournalMonthStart(periodStart);
      await taskActions.requireOpen(entryId: entryId);
      await _requireMonthlyTaskDestination(
        entryId: entryId,
        periodStart: periodStart,
      );
      final MonthlyLogSnapshot destination = await monthlyLog.loadOrCreate(
        periodStart,
      );
      await service.migrate(
        sourceEntryId: entryId,
        destinationOwner: JournalLogOwner(
          logId: destination.logId,
          monthlySection: JournalMonthlySection.tasks,
        ),
      );
    });
  }

  Future<void> migrateFutureEventToMonthlyCalendar({
    required String entryId,
    required String periodStart,
    required String calendarDate,
  }) {
    return run(() async {
      validateJournalMonthStart(periodStart);
      validateJournalMethodDate(calendarDate);
      await _requireFutureEventCalendarDestination(
        entryId: entryId,
        periodStart: periodStart,
        calendarDate: calendarDate,
      );
      final MonthlyLogSnapshot destination = await monthlyLog.loadOrCreate(
        periodStart,
      );
      await service.migrate(
        sourceEntryId: entryId,
        destinationOwner: JournalLogOwner(
          logId: destination.logId,
          monthlySection: JournalMonthlySection.calendar,
          monthlyCalendarDate: calendarDate,
        ),
      );
    });
  }

  Future<void> migrateTaskToCollection({
    required String entryId,
    required String collectionId,
  }) {
    return run(() async {
      await taskActions.requireOpen(entryId: entryId);
      await service.migrate(
        sourceEntryId: entryId,
        destinationOwner: JournalCollectionOwner(collectionId),
      );
    });
  }

  Future<void> scheduleTaskToFuture({
    required String entryId,
    required String periodStart,
  }) {
    return run(() async {
      await taskActions.requireOpen(entryId: entryId);
      final FutureLogSnapshot destination = await futureLog.loadOrCreate(
        periodStart,
      );
      await service.schedule(
        sourceEntryId: entryId,
        futureLogOwner: JournalLogOwner(logId: destination.logId),
      );
    });
  }

  Future<void> completeTask({required String entryId}) {
    return run(() => taskActions.complete(entryId: entryId));
  }

  Future<void> discardTask({required String entryId}) {
    return run(() => taskActions.discard(entryId: entryId));
  }

  Future<void> _requireForwardDailyDestination({
    required String entryId,
    required String methodDate,
  }) async {
    final row = await database
        .customSelect(
          '''
          SELECT l.kind, l.period_start
          FROM entry_placements p
          LEFT JOIN logs l ON l.id = p.log_id
          WHERE p.entry_id = ?
          ''',
          variables: <Variable<Object>>[Variable.withString(entryId)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw JournalNotFoundException('Entry placement', entryId);
    }

    final String? sourceKind = row.readNullable<String>('kind');
    final String? sourcePeriod = row.readNullable<String>('period_start');
    if (sourceKind == JournalLogKind.daily.code &&
        sourcePeriod != null &&
        methodDate.compareTo(sourcePeriod) <= 0) {
      throw const JournalInvariantException(
        'Daily Task migration must move to a later Daily Log.',
      );
    }
  }

  Future<void> _requireMonthlyTaskDestination({
    required String entryId,
    required String periodStart,
  }) async {
    final row = await database
        .customSelect(
          '''
          SELECT l.kind, l.period_start
          FROM entry_placements p
          LEFT JOIN logs l ON l.id = p.log_id
          WHERE p.entry_id = ?
          ''',
          variables: <Variable<Object>>[Variable.withString(entryId)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw JournalNotFoundException('Entry placement', entryId);
    }

    final String? sourceKind = row.readNullable<String>('kind');
    final String? sourcePeriod = row.readNullable<String>('period_start');
    if (sourceKind == JournalLogKind.monthly.code) {
      if (sourcePeriod == null || periodStart.compareTo(sourcePeriod) <= 0) {
        throw const JournalInvariantException(
          'Monthly Task migration must move to a later Monthly Log.',
        );
      }
      return;
    }
    if (sourceKind == JournalLogKind.future.code) {
      if (sourcePeriod != periodStart) {
        throw const JournalInvariantException(
          'An arrived Future Task can migrate only to the matching Monthly Log.',
        );
      }
      return;
    }
    throw const JournalInvariantException(
      'Monthly Task migration requires a Monthly or Future source.',
    );
  }

  Future<void> _requireFutureEventCalendarDestination({
    required String entryId,
    required String periodStart,
    required String calendarDate,
  }) async {
    if (!calendarDate.startsWith(periodStart.substring(0, 7))) {
      throw const JournalInvariantException(
        'Future Event migration must choose a day in the matching month.',
      );
    }
    final row = await database
        .customSelect(
          '''
          SELECT e.entry_type, l.kind, l.period_start,
                 CASE WHEN m.source_entry_id IS NULL THEN 0 ELSE 1 END
                   AS has_outgoing_migration
          FROM entries e
          JOIN entry_placements p ON p.entry_id = e.id
          LEFT JOIN logs l ON l.id = p.log_id
          LEFT JOIN migrations m ON m.source_entry_id = e.id
          WHERE e.id = ?
          ''',
          variables: <Variable<Object>>[Variable.withString(entryId)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw JournalNotFoundException('Entry', entryId);
    }
    if (row.read<String>('entry_type') != JournalEntryType.event.code ||
        row.readNullable<String>('kind') != JournalLogKind.future.code ||
        row.readNullable<String>('period_start') != periodStart) {
      throw const JournalInvariantException(
        'Monthly Calendar migration requires an Event from the matching Future Log.',
      );
    }
    if (row.read<int>('has_outgoing_migration') != 0) {
      throw const JournalInvariantException(
        'An entry may have only one direct outgoing migration.',
      );
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }

    _closing = true;
    await _operationTail;

    if (_closed) {
      return;
    }
    _closed = true;

    try {
      await database.close();
    } finally {
      _keyMaterial.destroy();
    }
  }
}

/// Creates, unlocks, locks, backs up, and restores the single local journal
/// used by the initial Daymark product flow.
///
/// An encrypted database without its key envelope, an envelope without its
/// database, or a leftover creation marker is never repaired or overwritten
/// automatically. Those states fail closed as [JournalStorageProblem].
final class JournalSessionManager {
  JournalSessionManager({
    required this.files,
    KeyEnvelopeService? keyEnvelopeService,
    EncryptedBackupService? backupService,
  }) : _keyEnvelopeService = keyEnvelopeService ?? KeyEnvelopeService(),
       _backupService = backupService ?? EncryptedBackupService();

  final JournalFiles files;
  final KeyEnvelopeService _keyEnvelopeService;
  final EncryptedBackupService _backupService;

  JournalSession? _session;

  Future<JournalAccessState> inspect() async {
    final JournalSession? session = _session;
    if (session != null && !session.isClosed) {
      return JournalUnlocked(session);
    }

    try {
      await _backupService.recoverInterruptedRestore(
        destinationJournalFile: files.databaseFile,
        destinationKeyEnvelopeFile: files.keyEnvelopeFile,
      );
    } on BackupRestoreException {
      return const JournalStorageProblem();
    }

    final bool databaseExists = await files.databaseFile.exists();
    final bool envelopeExists = await files.keyEnvelopeFile.exists();
    final bool creatingEnvelopeExists = await files.creatingKeyEnvelopeFile
        .exists();

    if (!databaseExists && !envelopeExists && !creatingEnvelopeExists) {
      return const JournalNeedsCreation();
    }

    if (databaseExists && envelopeExists && !creatingEnvelopeExists) {
      final int databaseLength = await files.databaseFile.length();
      final int envelopeLength = await files.keyEnvelopeFile.length();
      if (databaseLength > 0 && envelopeLength > 0) {
        return const JournalLocked();
      }
    }

    return const JournalStorageProblem();
  }

  Future<JournalSession> create({required String masterPassword}) async {
    if (masterPassword.isEmpty) {
      throw ArgumentError('A master password is required.');
    }

    final JournalAccessState accessState = await inspect();
    if (accessState is! JournalNeedsCreation) {
      throw StateError('A new journal can only be created in empty storage.');
    }

    await files.ensureDirectory();

    final JournalKeyMaterial keyMaterial = JournalKeyMaterial.generate();
    DaymarkDatabase? database;

    try {
      final String encodedEnvelope = await _keyEnvelopeService.wrap(
        masterPassword: masterPassword,
        keyMaterial: keyMaterial,
      );

      await files.creatingKeyEnvelopeFile.writeAsString(
        encodedEnvelope,
        flush: true,
      );

      database = await EncryptedDaymarkDatabase.createNew(
        file: files.databaseFile,
        keyMaterial: keyMaterial,
      );
      await _ensureJournalMetadata(database);

      await files.creatingKeyEnvelopeFile.rename(files.keyEnvelopeFile.path);

      final JournalSession session = JournalSession._(database, keyMaterial);
      _session = session;
      return session;
    } catch (error, stackTrace) {
      try {
        await database?.close();
      } finally {
        keyMaterial.destroy();
        await _cleanupFailedCreation();
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<JournalSession> unlock({required String masterPassword}) async {
    if (masterPassword.isEmpty) {
      throw ArgumentError('A master password is required.');
    }

    final JournalAccessState accessState = await inspect();
    if (accessState is! JournalLocked) {
      throw StateError('Only a complete locked journal can be unlocked.');
    }

    JournalKeyMaterial? keyMaterial;
    DaymarkDatabase? database;

    try {
      keyMaterial = await _keyEnvelopeService.unwrap(
        masterPassword: masterPassword,
        encodedEnvelope: await files.keyEnvelopeFile.readAsString(),
      );
      database = await EncryptedDaymarkDatabase.openExisting(
        file: files.databaseFile,
        keyMaterial: keyMaterial,
      );
      await _ensureJournalMetadata(database);

      final JournalSession session = JournalSession._(database, keyMaterial);
      _session = session;
      return session;
    } catch (error, stackTrace) {
      try {
        await database?.close();
      } finally {
        keyMaterial?.destroy();
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> reauthenticate({required String masterPassword}) async {
    if (masterPassword.isEmpty) {
      throw ArgumentError('A master password is required.');
    }

    final JournalSession? session = _session;
    if (session == null || session.isClosed) {
      throw StateError('An unlocked journal is required for reauthentication.');
    }

    await session.run(() async {
      JournalKeyMaterial? verificationMaterial;
      try {
        verificationMaterial = await _keyEnvelopeService.unwrap(
          masterPassword: masterPassword,
          encodedEnvelope: await files.keyEnvelopeFile.readAsString(),
        );
      } finally {
        verificationMaterial?.destroy();
      }
    });
  }

  Future<void> createBackup({
    required File backupFile,
    required String masterPassword,
  }) async {
    if (masterPassword.isEmpty) {
      throw ArgumentError('A master password is required.');
    }

    final JournalSession? session = _session;
    if (session == null || session.isClosed) {
      throw StateError('An unlocked journal is required to create a backup.');
    }

    await session.run(() async {
      await _backupService.createBackup(
        journalFile: files.databaseFile,
        backupFile: backupFile,
        keyMaterial: session._keyMaterial,
        encodedKeyEnvelope: await files.keyEnvelopeFile.readAsString(),
        masterPassword: masterPassword,
      );
    });
  }

  Future<JournalSession> restoreBackup({
    required File backupFile,
    required String masterPassword,
  }) async {
    if (masterPassword.isEmpty) {
      throw ArgumentError('A master password is required.');
    }

    final JournalAccessState accessState = await inspect();
    if (accessState is! JournalLocked && accessState is! JournalNeedsCreation) {
      throw StateError(
        'A backup can only be restored while the journal is locked or absent.',
      );
    }

    await files.ensureDirectory();
    await _backupService.restoreBackup(
      backupFile: backupFile,
      destinationJournalFile: files.databaseFile,
      destinationKeyEnvelopeFile: files.keyEnvelopeFile,
      masterPassword: masterPassword,
    );

    return unlock(masterPassword: masterPassword);
  }

  Future<void> lock() async {
    final JournalSession? session = _session;
    _session = null;
    await session?.close();
  }

  Future<void> dispose() => lock();

  Future<void> _ensureJournalMetadata(DaymarkDatabase database) async {
    await database.transaction(() async {
      final rows = await database
          .customSelect('SELECT id FROM journal_metadata ORDER BY id LIMIT 2')
          .get();

      if (rows.length > 1) {
        throw StateError('Journal metadata contains more than one row.');
      }
      if (rows.isNotEmpty) {
        return;
      }

      final int nowUtcMicros = DateTime.now().toUtc().microsecondsSinceEpoch;
      await database.customStatement(
        'INSERT INTO journal_metadata (id, created_at, updated_at) '
        'VALUES (?, ?, ?)',
        <Object?>[const Uuid().v7(), nowUtcMicros, nowUtcMicros],
      );
    });
  }

  Future<void> _cleanupFailedCreation() async {
    await _deleteIfExists(files.creatingKeyEnvelopeFile);
    await _deleteIfExists(files.keyEnvelopeFile);
    await _deleteIfExists(files.databaseFile);
  }
}

Future<void> _deleteIfExists(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } on FileSystemException {
    // Preserve the original creation failure. A file that could not be
    // removed is detected as JournalStorageProblem on the next inspection.
  }
}
