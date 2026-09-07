from pathlib import Path
import json


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"expected source block not found in {path}")
    file.write_text(text.replace(old, new, 1))


def insert_json_after_key(path: str, anchor_key: str, values: list[tuple[str, str]]) -> None:
    file = Path(path)
    text = file.read_text()
    if all(f'"{key}"' in text for key, _ in values):
        return
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if f'"{anchor_key}"' not in line:
            continue
        indent = line[: len(line) - len(line.lstrip())]
        additions = [
            f'{indent}"{key}": {json.dumps(value, ensure_ascii=False)},'
            for key, value in values
        ]
        lines[index + 1:index + 1] = additions
        file.write_text('\n'.join(lines) + '\n')
        return
    raise SystemExit(f"anchor key {anchor_key} not found in {path}")


session_path = "lib/core/session/journal_session.dart"
replace_once(
    session_path,
    """  Future<void> migrateTaskToDaily({
    required String entryId,
    required String methodDate,
  }) {
    return run(() async {
      await taskActions.requireOpen(entryId: entryId);
      final DailyLogSnapshot destination = await dailyLog.loadOrCreate(
        methodDate,
      );
      await service.migrate(
        sourceEntryId: entryId,
        destinationOwner: JournalLogOwner(logId: destination.logId),
      );
    });
  }

  Future<void> migrateTaskToCollection({
""",
    """  Future<void> migrateTaskToDaily({
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

  Future<void> migrateTaskToCollection({
""",
)
replace_once(
    session_path,
    """  Future<void> discardTask({required String entryId}) {
    return run(() => taskActions.discard(entryId: entryId));
  }

  Future<void> close() async {
""",
    """  Future<void> discardTask({required String entryId}) {
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

  Future<void> close() async {
""",
)

migration_dialog = "lib/features/journal/presentation/task_migration_dialog.dart"
replace_once(
    migration_dialog,
    "import 'package:daymark/features/journal/data/daily_log_repository.dart';\n",
    "import 'package:daymark/features/journal/data/daily_log_repository.dart';\nimport 'package:daymark/features/journal/data/monthly_log_repository.dart';\n",
)
replace_once(
    migration_dialog,
    """final class _SessionDailyTaskMigrationDataSource
    implements DailyTaskMigrationDataSource {
  const _SessionDailyTaskMigrationDataSource(this._session);

  final JournalSession _session;

  @override
  Future<void> migrateTask({
    required String entryId,
    required String methodDate,
  }) {
    return _session.migrateTaskToDaily(
      entryId: entryId,
      methodDate: methodDate,
    );
  }
}

enum TaskMigrationDestination { nextDay, date, collection }

Future<TaskMigrationDestination?> showTaskMigrationDestinationDialog({
  required BuildContext context,
}) {
""",
    """final class _SessionDailyTaskMigrationDataSource
    implements DailyTaskMigrationDataSource {
  const _SessionDailyTaskMigrationDataSource(this._session);

  final JournalSession _session;

  @override
  Future<void> migrateTask({
    required String entryId,
    required String methodDate,
  }) {
    return _session.migrateTaskToDaily(
      entryId: entryId,
      methodDate: methodDate,
    );
  }
}

abstract interface class MonthlyTaskMigrationDataSource {
  Future<void> migrateTask({
    required String entryId,
    required String periodStart,
  });
}

final Provider<MonthlyTaskMigrationDataSource>
monthlyTaskMigrationDataSourceProvider = Provider<MonthlyTaskMigrationDataSource>((
  ref,
) {
  final JournalAccessState access = ref
      .watch(journalSessionControllerProvider)
      .requireValue;
  if (access case JournalUnlocked(:final session)) {
    return _SessionMonthlyTaskMigrationDataSource(session);
  }
  throw StateError(
    'Monthly Task migration requires an unlocked journal session.',
  );
});

final class _SessionMonthlyTaskMigrationDataSource
    implements MonthlyTaskMigrationDataSource {
  const _SessionMonthlyTaskMigrationDataSource(this._session);

  final JournalSession _session;

  @override
  Future<void> migrateTask({
    required String entryId,
    required String periodStart,
  }) {
    return _session.migrateTaskToMonthlyTasks(
      entryId: entryId,
      periodStart: periodStart,
    );
  }
}

enum TaskMigrationDestination { nextDay, date, nextMonth, collection }

Future<TaskMigrationDestination?> showTaskMigrationDestinationDialog({
  required BuildContext context,
  bool includeNextMonth = false,
}) {
""",
)
replace_once(
    migration_dialog,
    """        SimpleDialogOption(
          key: const ValueKey<String>('migrate-collection'),
""",
    """        if (includeNextMonth)
          SimpleDialogOption(
            key: const ValueKey<String>('migrate-next-month'),
            onPressed: () {
              Navigator.of(dialogContext)
                  .pop(TaskMigrationDestination.nextMonth);
            },
            child: Text(l10n.nextMonth),
          ),
        SimpleDialogOption(
          key: const ValueKey<String>('migrate-collection'),
""",
)
replace_once(
    migration_dialog,
    """String nextTaskMigrationMethodDate(DateTime anchor) {
  final DateTime dateOnly = DateTime(anchor.year, anchor.month, anchor.day);
  return formatJournalMethodDate(dateOnly.add(const Duration(days: 1)));
}

Future<String?> showTaskDailyMigrationDatePicker({
""",
    """String nextTaskMigrationMethodDate(DateTime anchor) {
  final DateTime dateOnly = DateTime(anchor.year, anchor.month, anchor.day);
  return formatJournalMethodDate(dateOnly.add(const Duration(days: 1)));
}

String nextTaskMigrationMonthStart(DateTime anchor) {
  return formatJournalMonthStart(DateTime(anchor.year, anchor.month + 1));
}

Future<String?> showTaskDailyMigrationDatePicker({
""",
)

monthly = "lib/features/journal/presentation/monthly_screen.dart"
replace_once(
    monthly,
    """    String? migrationMethodDate;
    String? migrationCollectionId;
    if (action == _MonthlyEntryAction.migrate) {
      final TaskMigrationDestination? destination =
          await showTaskMigrationDestinationDialog(context: context);
""",
    """    String? migrationMethodDate;
    String? migrationMonthStart;
    String? migrationCollectionId;
    if (action == _MonthlyEntryAction.migrate) {
      final TaskMigrationDestination? destination =
          await showTaskMigrationDestinationDialog(
            context: context,
            includeNextMonth: true,
          );
""",
)
replace_once(
    monthly,
    """        case TaskMigrationDestination.collection:
          migrationCollectionId = await showTaskCollectionMigrationDialog(
""",
    """        case TaskMigrationDestination.nextMonth:
          migrationMonthStart = nextTaskMigrationMonthStart(actionMonth);
          break;
        case TaskMigrationDestination.collection:
          migrationCollectionId = await showTaskCollectionMigrationDialog(
""",
)
replace_once(
    monthly,
    """          if (migrationMethodDate != null) {
            await ref
                .read(dailyTaskMigrationDataSourceProvider)
                .migrateTask(
                  entryId: entry.id,
                  methodDate: migrationMethodDate,
                );
          } else {
            await ref
                .read(taskCollectionMigrationDataSourceProvider)
                .migrateTask(
                  entryId: entry.id,
                  collectionId: migrationCollectionId!,
                );
          }
""",
    """          if (migrationMethodDate != null) {
            await ref
                .read(dailyTaskMigrationDataSourceProvider)
                .migrateTask(
                  entryId: entry.id,
                  methodDate: migrationMethodDate,
                );
          } else if (migrationMonthStart != null) {
            await ref
                .read(monthlyTaskMigrationDataSourceProvider)
                .migrateTask(
                  entryId: entry.id,
                  periodStart: migrationMonthStart,
                );
          } else {
            await ref
                .read(taskCollectionMigrationDataSourceProvider)
                .migrateTask(
                  entryId: entry.id,
                  collectionId: migrationCollectionId!,
                );
          }
""",
)

future = "lib/features/journal/presentation/future_screen.dart"
replace_once(
    future,
    "import 'package:daymark/core/session/journal_session.dart';\n",
    "import 'package:daymark/core/session/journal_future_history_session.dart';\nimport 'package:daymark/core/session/journal_session.dart';\n",
)
replace_once(
    future,
    "import 'package:flutter_riverpod/flutter_riverpod.dart';\n",
    "import 'package:flutter_riverpod/flutter_riverpod.dart';\nimport 'package:go_router/go_router.dart';\n",
)
replace_once(
    future,
    """abstract interface class FutureJournalDataSource {
  Future<FutureLogSnapshot> load(String periodStart);

  Future<void> capture({
""",
    """abstract interface class FutureJournalDataSource {
  Future<FutureLogSnapshot> load(String periodStart);

  Future<FutureLogSnapshot?> find(String periodStart);

  Future<void> capture({
""",
)
replace_once(
    future,
    """  @override
  Future<void> capture({
""",
    """  @override
  Future<FutureLogSnapshot?> find(String periodStart) {
    return _session.findFutureLog(periodStart);
  }

  @override
  Future<void> capture({
""",
)
replace_once(
    future,
    """  late DateTime _selectedMonth;
  late Future<List<FutureLogSnapshot>> _snapshotsFuture;
""",
    """  late DateTime _selectedMonth;
  late Future<List<FutureLogSnapshot>> _snapshotsFuture;
  late Future<FutureLogSnapshot?> _arrivedSnapshotFuture;
""",
)
replace_once(
    future,
    """    _selectedMonth = _months.first;
    _snapshotsFuture = _loadSnapshots();
    _scheduleHorizonRollover();
""",
    """    _selectedMonth = _months.first;
    _snapshotsFuture = _loadSnapshots();
    _arrivedSnapshotFuture = _loadArrivedSnapshot();
    _scheduleHorizonRollover();
""",
)
replace_once(
    future,
    """    if (_sectionScopeInitialized &&
        isFutureSectionActive &&
        !_wasFutureSectionActive) {
      _snapshotsFuture = _loadSnapshots();
      _restoreComposerFocus();
    }
""",
    """    if (_sectionScopeInitialized &&
        isFutureSectionActive &&
        !_wasFutureSectionActive) {
      _snapshotsFuture = _loadSnapshots();
      _arrivedSnapshotFuture = _loadArrivedSnapshot();
      _restoreComposerFocus();
    }
""",
)
replace_once(
    future,
    """          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<FutureLogSnapshot>>(
""",
    """          FutureBuilder<FutureLogSnapshot?>(
            future: _arrivedSnapshotFuture,
            builder: (context, snapshot) {
              final FutureLogSnapshot? arrived = snapshot.data;
              final bool hasOpenTasks =
                  arrived?.entries.any(
                    (entry) =>
                        entry.type == JournalEntryType.task &&
                        entry.taskState == JournalTaskState.open,
                  ) ??
                  false;
              if (!hasOpenTasks) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey<String>('review-arrived-future'),
                    onPressed: () => context.go('/future/${arrived!.periodStart}'),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(l10n.reviewCurrentFutureLog),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<FutureLogSnapshot>>(
""",
)
replace_once(
    future,
    """  Future<List<FutureLogSnapshot>> _loadSnapshots() {
    final FutureJournalDataSource dataSource = _dataSource();
    return Future.wait([
      for (final DateTime month in _months)
        dataSource.load(formatFuturePeriodStart(month)),
    ]);
  }

  Future<void> _capture() async {
""",
    """  Future<List<FutureLogSnapshot>> _loadSnapshots() {
    final FutureJournalDataSource dataSource = _dataSource();
    return Future.wait([
      for (final DateTime month in _months)
        dataSource.load(formatFuturePeriodStart(month)),
    ]);
  }

  Future<FutureLogSnapshot?> _loadArrivedSnapshot() {
    return _dataSource().find(formatFuturePeriodStart(_anchorMonth));
  }

  Future<void> _capture() async {
""",
)
replace_once(
    future,
    """    if (currentMonth == _anchorMonth) {
      _scheduleHorizonRollover();
      return;
    }
""",
    """    if (currentMonth == _anchorMonth) {
      setState(() {
        _arrivedSnapshotFuture = _loadArrivedSnapshot();
      });
      _scheduleHorizonRollover();
      return;
    }
""",
)
replace_once(
    future,
    """      _selectedMonth = selectedIndex >= 0
          ? months[selectedIndex]
          : months.first;
      _snapshotsFuture = _loadSnapshots();
    });
""",
    """      _selectedMonth = selectedIndex >= 0
          ? months[selectedIndex]
          : months.first;
      _snapshotsFuture = _loadSnapshots();
      _arrivedSnapshotFuture = _loadArrivedSnapshot();
    });
""",
)

future_history = "lib/features/journal/presentation/future_history_screen.dart"
replace_once(
    future_history,
    "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:flutter/foundation.dart';\n",
)
replace_once(
    future_history,
    "import 'entry_semantics.dart';\n",
    "import 'entry_semantics.dart';\nimport 'task_migration_dialog.dart';\n",
)
replace_once(
    future_history,
    """abstract interface class FutureHistoryDataSource {
  Future<FutureLogSnapshot?> find(String periodStart);
}
""",
    """abstract interface class FutureHistoryDataSource {
  Future<FutureLogSnapshot?> find(String periodStart);

  Future<void> completeTask({required String entryId});

  Future<void> discardTask({required String entryId});
}
""",
)
replace_once(
    future_history,
    """  @override
  Future<FutureLogSnapshot?> find(String periodStart) {
    return _session.findFutureLog(periodStart);
  }
}

class FutureHistoryScreen extends ConsumerStatefulWidget {
  const FutureHistoryScreen({required this.periodStart, super.key});

  final String periodStart;
""",
    """  @override
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
  const FutureHistoryScreen({
    required this.periodStart,
    this.now,
    super.key,
  });

  final String periodStart;
  final DateTime Function()? now;
""",
)
replace_once(
    future_history,
    """class _FutureHistoryScreenState extends ConsumerState<FutureHistoryScreen> {
  late final DateTime _month;
  late final Future<FutureLogSnapshot?> _snapshotFuture;
""",
    """class _FutureHistoryScreenState extends ConsumerState<FutureHistoryScreen> {
  late final DateTime _month;
  late Future<FutureLogSnapshot?> _snapshotFuture;
  late final bool _arrivedCurrentMonth;
  String? _entryActionId;
""",
)
replace_once(
    future_history,
    """    validateFuturePeriodStart(widget.periodStart);
    _month = DateTime.parse(widget.periodStart);
    _snapshotFuture = _dataSource().find(widget.periodStart);
""",
    """    validateFuturePeriodStart(widget.periodStart);
    _month = DateTime.parse(widget.periodStart);
    final DateTime now = _now();
    _arrivedCurrentMonth =
        _month.year == now.year && _month.month == now.month;
    _snapshotFuture = _dataSource().find(widget.periodStart);
""",
)
replace_once(
    future_history,
    """          const SizedBox(height: 8),
          Text(
            l10n.futureHistoryReadOnly,
            style: Theme.of(context).textTheme.bodySmall,
          ),
""",
    """          const SizedBox(height: 8),
          Text(
            _arrivedCurrentMonth
                ? l10n.futureArrivalReviewPrompt
                : l10n.futureHistoryReadOnly,
            style: Theme.of(context).textTheme.bodySmall,
          ),
""",
)
replace_once(
    future_history,
    """  Widget _buildEntries(BuildContext context, List<FutureLogEntry> entries) {
    return ListView.separated(
""",
    """  Widget _buildEntries(BuildContext context, List<FutureLogEntry> entries) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListView.separated(
""",
)
replace_once(
    future_history,
    """        final bool discarded = entry.taskState == JournalTaskState.discarded;
        final TextStyle? style = Theme.of(context).textTheme.bodyLarge;
        final TextStyle? markerStyle = Theme.of(context).textTheme.titleMedium;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  _futureHistoryEntrySymbol(entry),
                  textAlign: TextAlign.center,
                  style: discarded
                      ? markerStyle?.copyWith(
                          decoration: TextDecoration.lineThrough,
                        )
                      : markerStyle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  label: journalEntrySemanticLabel(
                    AppLocalizations.of(context),
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
          ),
        );
""",
    """        final bool discarded = entry.taskState == JournalTaskState.discarded;
        final bool actionInProgress = _entryActionId == entry.id;
        final bool openTask =
            entry.type == JournalEntryType.task &&
            entry.taskState == JournalTaskState.open;
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
                        ? style?.copyWith(decoration: TextDecoration.lineThrough)
                        : style,
                  ),
                ),
              ),
            ),
          ],
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: !_arrivedCurrentMonth || !openTask || actionInProgress
              ? row
              : SizedBox(
                  width: double.infinity,
                  child: PopupMenuButton<_FutureArrivalAction>(
                    enabled: _entryActionId == null,
                    tooltip: l10n.taskActions,
                    padding: EdgeInsets.zero,
                    onSelected: (action) {
                      _applyArrivalAction(entry, action);
                    },
                    itemBuilder: (context) => <PopupMenuEntry<_FutureArrivalAction>>[
                      PopupMenuItem<_FutureArrivalAction>(
                        value: _FutureArrivalAction.migrateToMonthly,
                        child: Text(l10n.migrateToCurrentMonth),
                      ),
                      PopupMenuItem<_FutureArrivalAction>(
                        value: _FutureArrivalAction.complete,
                        child: Text(l10n.completeTask),
                      ),
                      PopupMenuItem<_FutureArrivalAction>(
                        value: _FutureArrivalAction.discard,
                        child: Text(l10n.discardTask),
                      ),
                    ],
                    child: row,
                  ),
                ),
        );
""",
)
replace_once(
    future_history,
    """  FutureHistoryDataSource _dataSource() {
    return ref.read(futureHistoryDataSourceProvider);
  }

  Future<void> _lock() {
""",
    """  Future<void> _applyArrivalAction(
    FutureLogEntry entry,
    _FutureArrivalAction action,
  ) async {
    if (!_arrivedCurrentMonth || _entryActionId != null) {
      return;
    }
    final bool openTask =
        entry.type == JournalEntryType.task &&
        entry.taskState == JournalTaskState.open;
    if (!openTask) {
      return;
    }

    setState(() => _entryActionId = entry.id);
    try {
      final FutureHistoryDataSource dataSource = _dataSource();
      switch (action) {
        case _FutureArrivalAction.migrateToMonthly:
          await ref
              .read(monthlyTaskMigrationDataSourceProvider)
              .migrateTask(
                entryId: entry.id,
                periodStart: widget.periodStart,
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
""",
)
replace_once(
    future_history,
    """String _futureHistoryEntrySymbol(FutureLogEntry entry) => switch (entry.type) {
""",
    """enum _FutureArrivalAction { migrateToMonthly, complete, discard }

String _futureHistoryEntrySymbol(FutureLogEntry entry) => switch (entry.type) {
""",
)

localizations = {
    "lib/l10n/app_en.arb": [
        ("reviewCurrentFutureLog", "Review arrived Future tasks"),
        ("futureArrivalReviewPrompt", "This Future Log month has arrived. Review each open Task and deliberately migrate it to the current Monthly Tasks, complete it, or discard it."),
        ("migrateToCurrentMonth", "Migrate to current month"),
    ],
    "lib/l10n/app_es.arb": [
        ("reviewCurrentFutureLog", "Revisar tareas futuras que ya llegaron"),
        ("futureArrivalReviewPrompt", "Este mes del Registro Futuro ya llegó. Revisa cada tarea abierta y decide si migrarla a las Tareas Mensuales actuales, completarla o descartarla."),
        ("migrateToCurrentMonth", "Migrar al mes actual"),
    ],
    "lib/l10n/app_pt.arb": [
        ("reviewCurrentFutureLog", "Revisar tarefas futuras que chegaram"),
        ("futureArrivalReviewPrompt", "Este mês do Registro Futuro chegou. Revise cada tarefa aberta e decida conscientemente se ela deve migrar para as Tarefas Mensais atuais, ser concluída ou descartada."),
        ("migrateToCurrentMonth", "Migrar para o mês atual"),
    ],
    "lib/l10n/app_pt_BR.arb": [
        ("reviewCurrentFutureLog", "Revisar tarefas futuras que chegaram"),
        ("futureArrivalReviewPrompt", "Este mês do Registro Futuro chegou. Revise cada tarefa aberta e decida conscientemente se ela deve migrar para as Tarefas Mensais atuais, ser concluída ou descartada."),
        ("migrateToCurrentMonth", "Migrar para o mês atual"),
    ],
}
for path, values in localizations.items():
    insert_json_after_key(path, "futureHistoryReadOnly", values)

session_test = "test/session/daily_task_migration_session_test.dart"
replace_once(
    session_test,
    "import 'package:daymark/features/journal/data/daily_log_repository.dart';\n",
    "import 'package:daymark/features/journal/data/daily_log_repository.dart';\nimport 'package:daymark/features/journal/data/future_log_repository.dart';\n",
)
replace_once(
    session_test,
    """  test('invalid source does not create a destination Daily Log', () async {
""",
    """  test('Daily Task migration rejects same-day and backward destinations', () async {
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
      session.migrateTaskToDaily(
        entryId: entryId,
        methodDate: '2026-09-07',
      ),
      throwsA(isA<JournalInvariantException>()),
    );
    await expectLater(
      session.migrateTaskToDaily(
        entryId: entryId,
        methodDate: '2026-09-06',
      ),
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
  });

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

    final migrations = await session.database
        .customSelect(
          '''
          SELECT source_entry_id, destination_entry_id, kind
          FROM migrations
          ORDER BY created_at, source_entry_id
          ''',
        )
        .get();
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
""",
)

doc = "docs/DAILY_TASK_MIGRATION_EXPERIMENT.md"
replace_once(
    doc,
    """Generic Task/Event/Note composers in **Today**, **Future**, and **Collections** accept the familiar Bullet Journal signifiers directly in the text field:
""",
    """Generic Task/Event/Note composers in **Today**, **Future**, and **Collections** accept the familiar Bullet Journal Bullets directly in the text field:
""",
)
replace_once(
    doc,
    """For an open Task in **Today** or the current **Monthly Tasks** section, **Migrate** offers three deliberate destinations:

1. **Next day** — migrate to the Daily Log immediately following the current method date.
2. **Date** — migrate to an explicitly selected future Daily Log date.
3. **Collection** — preserve the existing migration-to-Collection behavior.

For Monthly Tasks, the Daily destination is anchored to the current method date, not to the first day of the Monthly Log.
""",
    """For an open Task in **Today**, **Migrate** offers three deliberate destinations:

1. **Next day** — migrate to the Daily Log immediately following the current method date.
2. **Date** — migrate to an explicitly selected future Daily Log date.
3. **Collection** — preserve the existing migration-to-Collection behavior.

For an open Task in the current **Monthly Tasks** section, the same choices are available plus **Next month**, which creates or reuses the next Monthly Log and places a fresh open Task in its Tasks section. The source remains in the current month with `>` state and lineage.

For Monthly Tasks, a Daily destination is anchored to the current method date, not to the first day of the Monthly Log.
""",
)
replace_once(
    doc,
    """## Migration semantics
""",
    """## Future arrival review

When a Future Log month becomes the current month, Daymark exposes a quiet review link only if that arrived Future bucket still contains open Tasks.

The arrived Future month is no longer treated as ordinary read-only history for those open Tasks. Each open Task can be deliberately:

- migrated into the matching current Monthly Tasks list;
- completed;
- discarded.

A Future Task migrated into Monthly keeps its Future source with `>` state, creates a fresh open Monthly Task, and records another lineage edge. If the Future Task originally came from scheduling, the journal therefore preserves the full chain: chronological source → Future destination → Monthly destination.

Future Events and Notes remain read-only in this experiment. Moving an Event into the Monthly Calendar would require an explicit day that the month-addressed Future entry does not contain, while Notes do not belong to either canonical Monthly section. The experiment does not invent those semantics.

## Migration semantics
""",
)
replace_once(
    doc,
    """The destination date must be later than the current method date in the experimental UI.
""",
    """The destination date must be later than the current method date in the experimental UI. The session layer also rejects same-day or backward Daily-to-Daily migration, so the forward-only rule is not dependent on UI validation.

Monthly-to-Monthly migration must target a later Monthly Log. Future-to-Monthly arrival migration must target the Monthly Log for the same month as the Future source.
""",
)
replace_once(
    doc,
    """- current Monthly Tasks can enter and leave reflection without affecting Calendar, Tracker, or historical Monthly views;
""",
    """- current Monthly Tasks can enter and leave reflection without affecting Calendar, Tracker, or historical Monthly views;
- Monthly Tasks can deliberately migrate into the next Monthly Tasks list while preserving source history and lineage;
- an arrived Future Task can deliberately migrate into the matching current Monthly Tasks list;
- a scheduled Task can preserve a two-edge lineage chain from original source through Future into Monthly;
- same-day and backward Daily-to-Daily migration is rejected before a destination is created;
""",
)
