import 'package:daymark/core/session/journal_session.dart';
import 'package:daymark/core/session/journal_session_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class MonthlyCalendarTaskDataSource {
  Future<void> capture({
    required String logId,
    required String calendarDate,
    required String content,
  });
}

final Provider<MonthlyCalendarTaskDataSource>
monthlyCalendarTaskDataSourceProvider = Provider<MonthlyCalendarTaskDataSource>(
  (ref) {
    final JournalAccessState access = ref
        .watch(journalSessionControllerProvider)
        .requireValue;
    if (access case JournalUnlocked(:final session)) {
      return _SessionMonthlyCalendarTaskDataSource(session);
    }
    throw StateError(
      'Monthly Calendar Task capture requires an unlocked journal session.',
    );
  },
);

final class _SessionMonthlyCalendarTaskDataSource
    implements MonthlyCalendarTaskDataSource {
  const _SessionMonthlyCalendarTaskDataSource(this._session);

  final JournalSession _session;

  @override
  Future<void> capture({
    required String logId,
    required String calendarDate,
    required String content,
  }) {
    return _session.captureMonthlyCalendarTask(
      logId: logId,
      calendarDate: calendarDate,
      content: content,
    );
  }
}
