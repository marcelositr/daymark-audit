import 'dart:async';

import 'package:daymark/core/session/journal_session.dart';
import 'package:daymark/core/session/journal_session_controller.dart';
import 'package:daymark/features/journal/data/daily_log_repository.dart';
import 'package:daymark/features/journal/data/tracker_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:daymark/presentation/app_section_scope.dart';
import 'package:daymark/presentation/daymark_controls.dart';
import 'package:daymark/presentation/daymark_empty_state.dart';
import 'package:daymark/presentation/daymark_notice.dart';
import 'package:daymark/presentation/daymark_page_frame.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'entry_capture_undo.dart';
import 'entry_collection_reference_dialog.dart';
import 'entry_semantics.dart';
import 'entry_signifiers.dart';
import 'journal_activity_guard.dart';
import 'rapid_log_input.dart';
import 'task_collection_migration_dialog.dart';
import 'task_migration_dialog.dart';
import 'task_schedule_dialog.dart';
import 'tracker_data_source.dart';
import 'tracker_visuals.dart';

abstract interface class TodayJournalDataSource {
  Future<DailyLogSnapshot> load(String methodDate);

  Future<void> capture({
    required String logId,
    required JournalEntryType type,
    required String content,
  });

  Future<void> completeTask({required String entryId});

  Future<void> scheduleTaskToFuture({
    required String entryId,
    required String periodStart,
  });

  Future<void> discardTask({required String entryId});
}

final Provider<TodayJournalDataSource> todayJournalDataSourceProvider =
    Provider<TodayJournalDataSource>((ref) {
      final JournalAccessState access = ref
          .watch(journalSessionControllerProvider)
          .requireValue;
      if (access case JournalUnlocked(:final session)) {
        return _SessionTodayJournalDataSource(session);
      }
      throw StateError('Today requires an unlocked journal session.');
    });

final class _SessionTodayJournalDataSource implements TodayJournalDataSource {
  const _SessionTodayJournalDataSource(this._session);

  final JournalSession _session;

  @override
  Future<DailyLogSnapshot> load(String methodDate) {
    return _session.loadDailyLog(methodDate);
  }

  @override
  Future<void> capture({
    required String logId,
    required JournalEntryType type,
    required String content,
  }) {
    return _session.captureDailyLogEntry(
      logId: logId,
      type: type,
      content: content,
    );
  }

  @override
  Future<void> completeTask({required String entryId}) {
    return _session.completeTask(entryId: entryId);
  }

  @override
  Future<void> scheduleTaskToFuture({
    required String entryId,
    required String periodStart,
  }) {
    return _session.scheduleTaskToFuture(
      entryId: entryId,
      periodStart: periodStart,
    );
  }

  @override
  Future<void> discardTask({required String entryId}) {
    return _session.discardTask(entryId: entryId);
  }
}

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen>
    with WidgetsBindingObserver {
  final TextEditingController _entryController = TextEditingController();
  final FocusNode _entryFocusNode = FocusNode();

  late DateTime _today;
  late Future<DailyLogSnapshot> _snapshotFuture;
  late Future<List<TrackerRecord>> _trackerFuture;
  Timer? _dayRolloverTimer;
  JournalEntryType _entryType = JournalEntryType.task;
  bool _saving = false;
  bool _reflecting = false;
  bool _sectionScopeInitialized = false;
  bool _wasTodaySectionActive = false;
  String? _entryActionId;
  String? _trackerActionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _today = _dateOnly(DateTime.now());
    _snapshotFuture = _loadSnapshot();
    _trackerFuture = _loadTrackers();
    _scheduleDayRollover();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final int? currentSectionIndex = AppSectionScope.maybeCurrentIndexOf(
      context,
    );
    if (currentSectionIndex == null) {
      return;
    }

    final bool isTodaySectionActive =
        currentSectionIndex == AppSectionScope.todaySectionIndex;
    if (_sectionScopeInitialized &&
        isTodaySectionActive &&
        !_wasTodaySectionActive) {
      setState(() {
        _trackerFuture = _loadTrackers();
      });
      if (!_reflecting &&
          !_saving &&
          _entryActionId == null &&
          _trackerActionId == null) {
        _restoreComposerFocus();
      }
    }

    _sectionScopeInitialized = true;
    _wasTodaySectionActive = isTodaySectionActive;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshDateIfNeeded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dayRolloverTimer?.cancel();
    _entryController.dispose();
    _entryFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool busy =
        _saving || _entryActionId != null || _trackerActionId != null;
    final MaterialLocalizations material = MaterialLocalizations.of(context);

    return DaymarkPageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: busy ? null : _openPreviousDay,
                tooltip: l10n.previousDay,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: busy ? null : _chooseDate,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                  ),
                  child: Text(
                    material.formatFullDate(_today),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ),
              IconButton(
                onPressed: null,
                tooltip: l10n.nextDay,
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                onPressed: busy ? null : _toggleReflection,
                tooltip: _reflecting
                    ? l10n.finishReflection
                    : l10n.startReflection,
                icon: Icon(
                  _reflecting ? Icons.fact_check : Icons.fact_check_outlined,
                ),
              ),
              IconButton(
                onPressed: _lock,
                tooltip: l10n.lockJournal,
                icon: const Icon(Icons.lock_outline),
              ),
            ],
          ),
          if (_reflecting) ...[
            const SizedBox(height: 8),
            Text(
              l10n.dailyReflectionPrompt,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else
            _buildTodayTrackers(l10n),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<DailyLogSnapshot>(
              future: _snapshotFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return Center(child: Text(l10n.dailyLogLoadFailed));
                }
                return _buildEntries(context, l10n, snapshot.requireData);
              },
            ),
          ),
          const DaymarkNoticeRegion(),
          if (!_reflecting) ...[
            const SizedBox(height: 12),
            _buildComposer(l10n),
          ],
        ],
      ),
    );
  }

  Widget _buildTodayTrackers(AppLocalizations l10n) {
    return FutureBuilder<List<TrackerRecord>>(
      future: _trackerFuture,
      builder:
          (BuildContext context, AsyncSnapshot<List<TrackerRecord>> snapshot) {
            if (snapshot.connectionState != ConnectionState.done ||
                snapshot.hasError ||
                !snapshot.hasData ||
                snapshot.requireData.isEmpty) {
              return const SizedBox.shrink();
            }

            final String methodDate = formatJournalMethodDate(_today);
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        l10n.todayTrackers,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      for (final TrackerRecord tracker in snapshot.requireData)
                        _buildTodayTrackerRow(l10n, tracker, methodDate),
                    ],
                  ),
                ),
              ),
            );
          },
    );
  }

  Widget _buildTodayTrackerRow(
    AppLocalizations l10n,
    TrackerRecord tracker,
    String methodDate,
  ) {
    final int value = tracker.valueOn(methodDate);
    final bool busy = _trackerActionId == tracker.id;
    final bool actionsBlocked =
        _saving || _entryActionId != null || _trackerActionId != null;
    final Color color = trackerSlotColors[tracker.colorSlot];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          DaymarkTrackerStripe(color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tracker.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...<Widget>[
            DaymarkTrackerMarkButton(
              tooltip: l10n.trackerFulfilled,
              selected: value == 1,
              color: color,
              onPressed: actionsBlocked
                  ? null
                  : () => _setTrackerMark(
                      tracker,
                      value == 1 && tracker.hasExplicitMark(methodDate)
                          ? null
                          : 1,
                    ),
              icon: Icons.check,
            ),
            DaymarkTrackerMarkButton(
              tooltip: l10n.trackerNotFulfilled,
              selected: value == -1,
              color: color,
              onPressed: actionsBlocked
                  ? null
                  : () => _setTrackerMark(
                      tracker,
                      value == -1 && tracker.hasExplicitMark(methodDate)
                          ? null
                          : -1,
                    ),
              icon: Icons.close,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEntries(
    BuildContext context,
    AppLocalizations l10n,
    DailyLogSnapshot snapshot,
  ) {
    final List<DailyLogEntry> visibleEntries = _reflecting
        ? <DailyLogEntry>[
            for (final DailyLogEntry entry in snapshot.entries)
              if (entry.type == JournalEntryType.task &&
                  entry.taskState == JournalTaskState.open)
                entry,
          ]
        : snapshot.entries;

    if (visibleEntries.isEmpty) {
      return DaymarkEmptyState(
        message: _reflecting ? l10n.dailyReflectionEmpty : l10n.emptyDailyLog,
        topPadding: 24,
      );
    }

    return ListView.separated(
      itemCount: visibleEntries.length,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final DailyLogEntry entry = visibleEntries[index];
        final TextStyle? entryStyle = Theme.of(context).textTheme.bodyLarge;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: _buildEntryRow(context, l10n, entry, entryStyle),
        );
      },
    );
  }

  Widget _buildEntryRow(
    BuildContext context,
    AppLocalizations l10n,
    DailyLogEntry entry,
    TextStyle? entryStyle,
  ) {
    final bool actionInProgress = _entryActionId == entry.id;
    final TextStyle? markerStyle = Theme.of(context).textTheme.titleMedium;
    final Widget marker = actionInProgress
        ? const Center(
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : Text(
            _entrySymbol(entry),
            textAlign: TextAlign.center,
            style: entry.taskState == JournalTaskState.discarded
                ? markerStyle?.copyWith(decoration: TextDecoration.lineThrough)
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
                style: entry.taskState == JournalTaskState.discarded
                    ? entryStyle?.copyWith(
                        decoration: TextDecoration.lineThrough,
                      )
                    : entryStyle,
              ),
            ),
          ),
        ),
      ],
    );
    if (actionInProgress) return row;

    final bool openTask =
        entry.type == JournalEntryType.task &&
        entry.taskState == JournalTaskState.open;
    return SizedBox(
      width: double.infinity,
      child: PopupMenuButton<_EntryAction>(
        enabled: _entryActionId == null,
        tooltip: l10n.entryActions,
        padding: EdgeInsets.zero,
        onSelected: (action) {
          unawaited(_applyEntryAction(entry, action));
        },
        itemBuilder: (context) => [
          if (openTask)
            PopupMenuItem(
              value: _EntryAction.complete,
              child: Text(l10n.completeTask),
            ),
          if (openTask)
            PopupMenuItem(
              value: _EntryAction.migrate,
              child: Text(l10n.migrateTask),
            ),
          if (openTask)
            PopupMenuItem(
              value: _EntryAction.schedule,
              child: Text(l10n.scheduleTask),
            ),
          if (!_reflecting)
            PopupMenuItem(
              value: _EntryAction.reference,
              child: Text(l10n.referenceEntry),
            ),
          if (!_reflecting)
            PopupMenuItem(
              value: _EntryAction.signifiers,
              child: Text(l10n.signifiers),
            ),
          if (openTask)
            PopupMenuItem(
              value: _EntryAction.discard,
              child: Text(l10n.discardTask),
            ),
        ],
        child: row,
      ),
    );
  }

  Widget _buildComposer(AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        DaymarkDropdownButton<JournalEntryType>(
          value: _entryType,
          onChanged: _saving
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _entryType = value);
                    _restoreComposerFocus();
                  }
                },
          items: [
            DropdownMenuItem(
              value: JournalEntryType.task,
              child: Text(l10n.entryTask),
            ),
            DropdownMenuItem(
              value: JournalEntryType.event,
              child: Text(l10n.entryEvent),
            ),
            DropdownMenuItem(
              value: JournalEntryType.note,
              child: Text(l10n.entryNote),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Focus(
            onKeyEvent: _handleComposerKeyEvent,
            child: TextField(
              controller: _entryController,
              focusNode: _entryFocusNode,
              autofocus: defaultTargetPlatform == TargetPlatform.linux,
              enabled: !_saving,
              minLines: 1,
              maxLines: 4,
              onChanged: (_) => JournalActivityGuard.recordActivity(context),
              decoration: InputDecoration(
                hintText: l10n.rapidLogHint,
                isDense: true,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _saving ? null : _capture,
          tooltip: l10n.addEntry,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_upward),
        ),
      ],
    );
  }

  TodayJournalDataSource _dataSource() {
    return ref.read(todayJournalDataSourceProvider);
  }

  TrackerDataSource _trackerDataSource() {
    return ref.read(trackerDataSourceProvider);
  }

  Future<DailyLogSnapshot> _loadSnapshot() {
    return _dataSource().load(formatJournalMethodDate(_today));
  }

  Future<List<TrackerRecord>> _loadTrackers() {
    return _trackerDataSource().loadForDay(formatJournalMethodDate(_today));
  }

  KeyEventResult _handleComposerKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isControlPressed) {
      unawaited(_capture());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _capture() async {
    final RapidLogInput rapidLog = parseRapidLogInput(
      _entryController.text,
      fallbackType: _entryType,
    );
    if (rapidLog.content.isEmpty || _saving) {
      return;
    }

    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _saving = true);

    try {
      final TodayJournalDataSource dataSource = _dataSource();
      final DailyLogSnapshot snapshot = await _snapshotFuture;
      final Set<String> beforeEntryIds = <String>{
        for (final DailyLogEntry entry in snapshot.entries) entry.id,
      };
      await dataSource.capture(
        logId: snapshot.logId,
        type: rapidLog.type,
        content: rapidLog.content,
      );
      final DailyLogSnapshot updatedSnapshot = await dataSource.load(
        formatJournalMethodDate(_today),
      );
      final List<String> capturedEntryIds = <String>[
        for (final DailyLogEntry entry in updatedSnapshot.entries)
          if (!beforeEntryIds.contains(entry.id)) entry.id,
      ];

      if (!mounted) return;
      _entryController.clear();
      setState(() {
        _snapshotFuture = Future<DailyLogSnapshot>.value(updatedSnapshot);
        _saving = false;
      });
      if (capturedEntryIds.length == 1) {
        _showCaptureUndo(capturedEntryIds.single);
      }
      _restoreComposerFocus();
    } catch (error, stackTrace) {
      _reportUnexpectedJournalError('capture', error, stackTrace);
      if (!mounted) {
        return;
      }
      ref.read(daymarkNoticeProvider.notifier).showError(l10n.saveEntryFailed);
      setState(() => _saving = false);
    }
  }

  Future<void> _setTrackerMark(TrackerRecord tracker, int? value) async {
    if (_trackerActionId != null) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String methodDate = formatJournalMethodDate(_today);
    setState(() => _trackerActionId = tracker.id);
    try {
      await _trackerDataSource().setMark(
        trackerId: tracker.id,
        methodDate: methodDate,
        value: value,
      );
      if (!mounted) return;
      setState(() {
        _trackerFuture = _loadTrackers();
        _trackerActionId = null;
      });
    } catch (error, stackTrace) {
      _reportUnexpectedJournalError('tracker mark', error, stackTrace);
      if (!mounted) return;
      setState(() => _trackerActionId = null);
      ref
          .read(daymarkNoticeProvider.notifier)
          .showError(l10n.trackerUpdateFailed);
    }
  }

  void _showCaptureUndo(String entryId) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    ref
        .read(daymarkNoticeProvider.notifier)
        .showUndo(
          message: l10n.entryCreated,
          actionLabel: l10n.undo,
          onUndo: () => _undoCapture(entryId),
        );
  }

  Future<void> _undoCapture(String entryId) async {
    JournalActivityGuard.recordActivity(context);
    try {
      await ref
          .read(entryCaptureUndoDataSourceProvider)
          .undoCapture(entryId: entryId);
      if (!mounted) return;
      setState(() {
        _snapshotFuture = _dataSource().load(formatJournalMethodDate(_today));
      });
      _restoreComposerFocus();
    } catch (error, stackTrace) {
      _reportUnexpectedJournalError('capture undo', error, stackTrace);
      if (!mounted) return;
      ref
          .read(daymarkNoticeProvider.notifier)
          .showError(AppLocalizations.of(context).undoCaptureFailed);
    }
  }

  Future<void> _applyEntryAction(
    DailyLogEntry entry,
    _EntryAction action,
  ) async {
    if (_entryActionId != null) {
      return;
    }
    final bool openTask =
        entry.type == JournalEntryType.task &&
        entry.taskState == JournalTaskState.open;
    if (action != _EntryAction.reference &&
        action != _EntryAction.signifiers &&
        !openTask) {
      return;
    }
    if (action == _EntryAction.signifiers) {
      try {
        await showEntrySignifierDialog(
          context: context,
          ref: ref,
          entryId: entry.id,
        );
      } catch (error, stackTrace) {
        _reportUnexpectedJournalError('signifiers', error, stackTrace);
        if (mounted) {
          ref
              .read(daymarkNoticeProvider.notifier)
              .showError(AppLocalizations.of(context).signifierUpdateFailed);
        }
      }
      return;
    }

    final DateTime actionDate = _today;
    String? migrationMethodDate;
    String? migrationCollectionId;
    if (action == _EntryAction.migrate) {
      final TaskMigrationDestination? destination =
          await showTaskMigrationDestinationDialog(context: context);
      if (!mounted || destination == null) {
        return;
      }

      switch (destination) {
        case TaskMigrationDestination.nextDay:
          migrationMethodDate = nextTaskMigrationMethodDate(actionDate);
          break;
        case TaskMigrationDestination.date:
          migrationMethodDate = await showTaskDailyMigrationDatePicker(
            context: context,
            anchor: actionDate,
          );
          if (!mounted || migrationMethodDate == null) {
            return;
          }
          break;
        case TaskMigrationDestination.nextMonth:
          return;
        case TaskMigrationDestination.collection:
          migrationCollectionId = await showTaskCollectionMigrationDialog(
            context: context,
            dataSource: ref.read(taskCollectionMigrationDataSourceProvider),
          );
          if (!mounted || migrationCollectionId == null) {
            return;
          }
          break;
      }
    }

    String? referenceCollectionId;
    if (action == _EntryAction.reference) {
      referenceCollectionId = await showEntryCollectionReferenceDialog(
        context: context,
        dataSource: ref.read(entryCollectionReferenceDataSourceProvider),
      );
      if (!mounted || referenceCollectionId == null) {
        return;
      }
    }

    String? schedulePeriodStart;
    if (action == _EntryAction.schedule) {
      schedulePeriodStart = await showTaskScheduleDialog(
        context: context,
        anchor: actionDate,
      );
      if (!mounted || schedulePeriodStart == null) {
        return;
      }
    }

    ref.read(daymarkNoticeProvider.notifier).dismiss();
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _entryActionId = entry.id);

    try {
      final TodayJournalDataSource dataSource = _dataSource();
      switch (action) {
        case _EntryAction.complete:
          await dataSource.completeTask(entryId: entry.id);
          break;
        case _EntryAction.migrate:
          if (migrationMethodDate != null) {
            final JournalAccessState access = ref
                .read(journalSessionControllerProvider)
                .requireValue;
            if (access case JournalUnlocked(:final session)) {
              await session.migrateTaskToDaily(
                entryId: entry.id,
                methodDate: migrationMethodDate,
              );
            } else {
              throw StateError(
                'Daily Task migration requires an unlocked journal session.',
              );
            }
          } else {
            await ref
                .read(taskCollectionMigrationDataSourceProvider)
                .migrateTask(
                  entryId: entry.id,
                  collectionId: migrationCollectionId!,
                );
          }
          break;
        case _EntryAction.schedule:
          await dataSource.scheduleTaskToFuture(
            entryId: entry.id,
            periodStart: schedulePeriodStart!,
          );
          break;
        case _EntryAction.reference:
          await ref
              .read(entryCollectionReferenceDataSourceProvider)
              .referenceEntry(
                entryId: entry.id,
                collectionId: referenceCollectionId!,
              );
          break;
        case _EntryAction.discard:
          await dataSource.discardTask(entryId: entry.id);
          break;
        case _EntryAction.signifiers:
          break;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _snapshotFuture = dataSource.load(formatJournalMethodDate(_today));
        _entryActionId = null;
      });
    } catch (error, stackTrace) {
      _reportUnexpectedJournalError(
        action == _EntryAction.reference
            ? 'collection reference'
            : 'task action',
        error,
        stackTrace,
      );
      if (!mounted) {
        return;
      }
      final String message = action == _EntryAction.reference
          ? l10n.referenceEntryFailed
          : l10n.taskActionFailed;
      ref.read(daymarkNoticeProvider.notifier).showError(message);
      setState(() => _entryActionId = null);
    }
  }

  void _toggleReflection() {
    if (_saving || _entryActionId != null || _trackerActionId != null) {
      return;
    }

    final bool enteringReflection = !_reflecting;
    setState(() => _reflecting = enteringReflection);
    if (enteringReflection) {
      _entryFocusNode.unfocus();
      return;
    }
    _restoreComposerFocus();
  }

  void _restoreComposerFocus() {
    if (defaultTargetPlatform != TargetPlatform.linux) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_reflecting && !_saving && _trackerActionId == null) {
        _entryFocusNode.requestFocus();
      }
    });
  }

  void _openPreviousDay() {
    final DateTime previousDate = _today.subtract(const Duration(days: 1));
    context.push('/daily/${formatJournalMethodDate(previousDate)}');
  }

  Future<void> _chooseDate() async {
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: _today,
      firstDate: DateTime(1900),
      lastDate: _today,
      initialEntryMode: DatePickerEntryMode.calendar,
      initialDatePickerMode: DatePickerMode.day,
    );
    if (!mounted || selected == null) {
      return;
    }
    final DateTime target = _dateOnly(selected);
    if (target == _today) {
      _restoreComposerFocus();
      return;
    }
    context.push('/daily/${formatJournalMethodDate(target)}');
  }

  Future<void> _lock() async {
    try {
      await ref.read(journalSessionControllerProvider.notifier).lock();
    } catch (error, stackTrace) {
      _reportUnexpectedJournalError('lock', error, stackTrace);
    }
  }

  void _refreshDateIfNeeded() {
    final DateTime currentDate = _dateOnly(DateTime.now());
    if (currentDate == _today) {
      if (mounted) {
        setState(() {
          _trackerFuture = _loadTrackers();
        });
      }
      _scheduleDayRollover();
      return;
    }

    if (mounted) {
      setState(() {
        _today = currentDate;
        _snapshotFuture = _loadSnapshot();
        _trackerFuture = _loadTrackers();
        _reflecting = false;
      });
    }
    _scheduleDayRollover();
    _restoreComposerFocus();
  }

  void _scheduleDayRollover() {
    _dayRolloverTimer?.cancel();
    final DateTime now = DateTime.now();
    final DateTime tomorrow = DateTime(now.year, now.month, now.day + 1);
    _dayRolloverTimer = Timer(
      tomorrow.difference(now) + const Duration(seconds: 1),
      _refreshDateIfNeeded,
    );
  }
}

enum _EntryAction {
  complete,
  migrate,
  schedule,
  reference,
  signifiers,
  discard,
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _entrySymbol(DailyLogEntry entry) => switch (entry.type) {
  JournalEntryType.task => switch (entry.taskState) {
    JournalTaskState.completed => '×',
    JournalTaskState.migrated => '>',
    JournalTaskState.scheduled => '<',
    JournalTaskState.discarded => '•',
    JournalTaskState.open => '•',
    null => '•',
  },
  JournalEntryType.event => '○',
  JournalEntryType.note => '–',
};

void _reportUnexpectedJournalError(
  String operation,
  Object error,
  StackTrace stackTrace,
) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: FlutterError(
        'Journal $operation failed (${error.runtimeType}).',
      ),
      stack: stackTrace,
      library: 'daymark',
    ),
  );
}
