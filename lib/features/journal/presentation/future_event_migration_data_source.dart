import 'package:daymark/core/session/journal_session.dart';
import 'package:daymark/core/session/journal_session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class FutureEventMigrationDataSource {
  Future<void> migrateToMonthlyCalendar({
    required String entryId,
    required String periodStart,
    required String calendarDate,
  });
}

final Provider<FutureEventMigrationDataSource>
futureEventMigrationDataSourceProvider =
    Provider<FutureEventMigrationDataSource>((ref) {
      final JournalAccessState access = ref
          .watch(journalSessionControllerProvider)
          .requireValue;
      if (access case JournalUnlocked(:final session)) {
        return _SessionFutureEventMigrationDataSource(session);
      }
      throw StateError(
        'Future Event migration requires an unlocked journal session.',
      );
    });

final class _SessionFutureEventMigrationDataSource
    implements FutureEventMigrationDataSource {
  const _SessionFutureEventMigrationDataSource(this._session);

  final JournalSession _session;

  @override
  Future<void> migrateToMonthlyCalendar({
    required String entryId,
    required String periodStart,
    required String calendarDate,
  }) {
    return _session.migrateFutureEventToMonthlyCalendar(
      entryId: entryId,
      periodStart: periodStart,
      calendarDate: calendarDate,
    );
  }
}
