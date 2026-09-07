import 'dart:async';

import 'package:daymark/core/session/journal_future_history_session.dart';
import 'package:daymark/core/session/journal_session.dart';
import 'package:daymark/core/session/journal_session_controller.dart';
import 'package:daymark/features/journal/data/future_log_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:daymark/presentation/daymark_empty_state.dart';
import 'package:daymark/presentation/daymark_notice.dart';
import 'package:daymark/presentation/daymark_page_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'entry_semantics.dart';
import 'entry_signifiers.dart';
import 'future_event_migration_data_source.dart';
import 'task_migration_dialog.dart';

abstract interface class FutureHistoryDataSource {
  Future<FutureLogSnapshot?> find(String periodStart);

  Future<void> completeTask({required String entryId});

  Future<void> discardTask({required String entryId});
}

final Provider<FutureHistoryDataSource> futureHistoryDataSourceProvider =
    Provider<FutureHistoryDataSource>((ref) {
      final JournalAccessState access = ref
          .watch(journalSessionControllerProvider)
          .requireValue;
      if (access case JournalUnlocked(:final session)) {
        return _SessionFutureHistoryDataSource(session);
      }
      throw StateError('Future history requires an unlocked journal session.');
    });

final class _SessionFutureHistoryDataSource implements FutureHistoryDataSource {
  const _SessionFutureHistoryDataSource(this._session);

  final JournalSession _session;

  @override
  Future<FutureLogSnapshot?> find(String periodStart) {
    return _session.findFutureLog(periodStart);
  }

  @override
  Future<void> completeTask({required String entryId}) {
    return _session.completeTask(entryId: entryId);
  }

  @override
  Future<void> discardTask({required String entryId}) {
    return _session.discardTask(entryId: entryId);
  }
}

class FutureHistoryScreen extends ConsumerStatefulWidget {
  const FutureHistoryScreen({required this.periodStart, this.now, super.key});

  final String periodStart;
  final DateTime Function()? now;

  @override
  ConsumerState<FutureHistoryScreen> createState() =>
      _FutureHistoryScreenState();
}

class _FutureHistoryScreenState extends ConsumerState<FutureHistoryScreen> {
  late final DateTime _month;
  late Future<FutureLogSnapshot?> _snapshotFuture;
  late final bool _arrivedCurrentMonth;
  String? _entryActionId;

  @override
  void initState() {
    super.initState();
    validateFuturePeriodStart(widget.periodStart);
    _month = DateTime.parse(widget.periodStart);
    final DateTime now = _now();
    _arrivedCurrentMonth = _month.year == now.year && _month.month == now.month;
    _snapshotFuture = _dataSource().find(widget.periodStart);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final MaterialLocalizations material = MaterialLocalizations.of(context);

    return DaymarkPageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => context.go('/future'),
                tooltip: material.backButtonTooltip,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  material.formatMonthYear(_month),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                onPressed: _lock,
                tooltip: l10n.lockJournal,
                icon: const Icon(Icons.lock_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _arrivedCurrentMonth
                ? l10n.futureArrivalReviewPrompt
                : l10n.futureHistoryReadOnly,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<FutureLogSnapshot?>(
              future: _snapshotFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(l10n.futureLogLoadFailed));
                }
                final FutureLogSnapshot? future = snapshot.data;
                if (future == null || future.entries.isEmpty) {
                  return DaymarkEmptyState(message: l10n.emptyFutureMonth);
                }
                return _buildEntries(context, future.entries);
              },
            ),
          ),
          const DaymarkNoticeRegion(),
        ],
      ),
    );
  }

  Widget _buildEntries(BuildContext context, List<FutureLogEntry> entries) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final FutureLogEntry entry = entries[index];
        final bool discarded = entry.taskState == JournalTaskState.discarded;
        final bool actionInProgress = _entryActionId == entry.id;
        final bool openTask =
            entry.type == JournalEntryType.task &&
            entry.taskState == JournalTaskState.open;
        final bool reviewableEvent =
            entry.type == JournalEntryType.event && !entry.hasOutgoingMigration;
        final TextStyle? style = Theme.of(context).textTheme.bodyLarge;
        final TextStyle? markerStyle = Theme.of(context).textTheme.titleMedium;
        final Widget marker = actionInProgress
            ? const Center(
                child: SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Text(
                _futureHistoryEntrySymbol(entry),
                textAlign: TextAlign.center,
                style: discarded
                    ? markerStyle?.copyWith(
                        decoration: TextDecoration.lineThrough,
                      )
                    : markerStyle,
              );
        final Widget row = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EntrySignifierMarks(entryId: entry.id),
            SizedBox(width: 28, child: marker),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                label: journalEntrySemanticLabel(
                  l10n,
                  type: entry.type,
                  taskState: entry.taskState,
                  content: entry.content,
                ),
                child: ExcludeSemantics(
                  child: Text(
                    entry.content,
                    style: discarded
                        ? style?.copyWith(
                            decoration: TextDecoration.lineThrough,
                          )
                        : style,
                  ),
                ),
              ),
            ),
          ],
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child:
              !_arrivedCurrentMonth ||
                  (!openTask && !reviewableEvent) ||
                  actionInProgress
              ? row
              : SizedBox(
                  width: double.infinity,
                  child: PopupMenuButton<_FutureArrivalAction>(
                    enabled: _entryActionId == null,
                    tooltip: l10n.taskActions,
                    padding: EdgeInsets.zero,
                    onSelected: (action) {
                      unawaited(_applyArrivalAction(entry, action));
                    },
                    itemBuilder: (context) =>
                        <PopupMenuEntry<_FutureArrivalAction>>[
                          if (openTask)
                            PopupMenuItem<_FutureArrivalAction>(
                              value: _FutureArrivalAction.migrateToMonthly,
                              child: Text(l10n.migrateToCurrentMonth),
                            ),
                          if (reviewableEvent)
                            PopupMenuItem<_FutureArrivalAction>(
                              value:
                                  _FutureArrivalAction.migrateEventToCalendar,
                              child: Text(l10n.migrateEventToCalendar),
                            ),
                          if (openTask)
                            PopupMenuItem<_FutureArrivalAction>(
                              value: _FutureArrivalAction.complete,
                              child: Text(l10n.completeTask),
                            ),
                          if (openTask)
                            PopupMenuItem<_FutureArrivalAction>(
                              value: _FutureArrivalAction.discard,
                              child: Text(l10n.discardTask),
                            ),
                        ],
                    child: row,
                  ),
                ),
        );
      },
    );
  }

  Future<void> _applyArrivalAction(
    FutureLogEntry entry,
    _FutureArrivalAction action,
  ) async {
    if (!_arrivedCurrentMonth || _entryActionId != null) {
      return;
    }
    final bool openTask =
        entry.type == JournalEntryType.task &&
        entry.taskState == JournalTaskState.open;
    final bool reviewableEvent =
        entry.type == JournalEntryType.event && !entry.hasOutgoingMigration;
    if (!openTask && !reviewableEvent) {
      return;
    }

    String? eventCalendarDate;
    if (action == _FutureArrivalAction.migrateEventToCalendar) {
      if (!reviewableEvent) {
        return;
      }
      final DateTime firstDate = DateTime(_month.year, _month.month);
      final DateTime lastDate = DateTime(_month.year, _month.month + 1, 0);
      final DateTime now = _now();
      final DateTime initialDate =
          now.isBefore(firstDate) || now.isAfter(lastDate) ? firstDate : now;
      final DateTime? selectedDate = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
      );
      if (!mounted || selectedDate == null) {
        return;
      }
      eventCalendarDate =
          '${selectedDate.year.toString().padLeft(4, '0')}-'
          '${selectedDate.month.toString().padLeft(2, '0')}-'
          '${selectedDate.day.toString().padLeft(2, '0')}';
    }

    setState(() => _entryActionId = entry.id);
    try {
      final FutureHistoryDataSource dataSource = _dataSource();
      switch (action) {
        case _FutureArrivalAction.migrateToMonthly:
          await ref
              .read(monthlyTaskMigrationDataSourceProvider)
              .migrateTask(entryId: entry.id, periodStart: widget.periodStart);
          break;
        case _FutureArrivalAction.migrateEventToCalendar:
          await ref
              .read(futureEventMigrationDataSourceProvider)
              .migrateToMonthlyCalendar(
                entryId: entry.id,
                periodStart: widget.periodStart,
                calendarDate: eventCalendarDate!,
              );
          break;
        case _FutureArrivalAction.complete:
          await dataSource.completeTask(entryId: entry.id);
          break;
        case _FutureArrivalAction.discard:
          await dataSource.discardTask(entryId: entry.id);
          break;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshotFuture = dataSource.find(widget.periodStart);
        _entryActionId = null;
      });
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: FlutterError(
            'Future arrival Task action failed (${error.runtimeType}).',
          ),
          stack: stackTrace,
          library: 'daymark',
        ),
      );
      if (!mounted) {
        return;
      }
      ref
          .read(daymarkNoticeProvider.notifier)
          .showError(AppLocalizations.of(context).taskActionFailed);
      setState(() => _entryActionId = null);
    }
  }

  FutureHistoryDataSource _dataSource() {
    return ref.read(futureHistoryDataSourceProvider);
  }

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  Future<void> _lock() {
    return ref.read(journalSessionControllerProvider.notifier).lock();
  }
}

enum _FutureArrivalAction {
  migrateToMonthly,
  migrateEventToCalendar,
  complete,
  discard,
}

String _futureHistoryEntrySymbol(FutureLogEntry entry) => switch (entry.type) {
  JournalEntryType.task => switch (entry.taskState) {
    JournalTaskState.completed => '×',
    JournalTaskState.migrated => '>',
    JournalTaskState.scheduled => '<',
    JournalTaskState.discarded => '•',
    JournalTaskState.open => '•',
    null => '•',
  },
  JournalEntryType.event => entry.hasOutgoingMigration ? '>' : '○',
  JournalEntryType.note => '–',
};
