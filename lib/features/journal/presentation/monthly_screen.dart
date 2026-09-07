import 'dart:async';

import 'package:daymark/core/session/journal_monthly_history_session.dart';
import 'package:daymark/core/session/journal_session.dart';
import 'package:daymark/core/session/journal_session_controller.dart';
import 'package:daymark/features/journal/data/monthly_log_repository.dart';
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
import 'monthly_calendar_task_data_source.dart';
import 'task_collection_migration_dialog.dart';
import 'task_migration_dialog.dart';
import 'task_schedule_dialog.dart';
import 'tracker_create_dialog.dart';
import 'tracker_data_source.dart';
import 'tracker_month_view.dart';

abstract interface class MonthlyJournalDataSource {
  Future<MonthlyLogSnapshot> load(String periodStart);

  Future<MonthlyLogSnapshot?> find(String periodStart);

  Future<void> captureCalendarEvent({
    required String logId,
    required String calendarDate,
    required String content,
  });

  Future<void> captureTask({required String logId, required String content});

  Future<void> completeTask({required String entryId});

  Future<void> scheduleTaskToFuture({
    required String entryId,
    required String periodStart,
  });

  Future<void> discardTask({required String entryId});
}

final Provider<MonthlyJournalDataSource> monthlyJournalDataSourceProvider =
    Provider<MonthlyJournalDataSource>((ref) {
      final JournalAccessState access = ref
          .watch(journalSessionControllerProvider)
          .requireValue;
      if (access case JournalUnlocked(:final session)) {
        return _SessionMonthlyJournalDataSource(session);
      }
      throw StateError('Monthly requires an unlocked journal session.');
    });

final class _SessionMonthlyJournalDataSource
    implements MonthlyJournalDataSource {
  const _SessionMonthlyJournalDataSource(this._session);

  final JournalSession _session;

  @override
  Future<MonthlyLogSnapshot> load(String periodStart) {
    return _session.loadMonthlyLog(periodStart);
  }

  @override
  Future<MonthlyLogSnapshot?> find(String periodStart) {
    return _session.findMonthlyLog(periodStart);
  }

  @override
  Future<void> captureCalendarEvent({
    required String logId,
    required String calendarDate,
    required String content,
  }) {
    return _session.captureMonthlyCalendarEvent(
      logId: logId,
      calendarDate: calendarDate,
      content: content,
    );
  }

  @override
  Future<void> captureTask({required String logId, required String content}) {
    return _session.captureMonthlyTask(logId: logId, content: content);
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

class MonthlyScreen extends ConsumerStatefulWidget {
  const MonthlyScreen({
    this.initialMonth,
    this.initialSection,
    this.now,
    super.key,
  });

  final DateTime? initialMonth;
  final JournalMonthlySection? initialSection;
  final DateTime Function()? now;

  @override
  ConsumerState<MonthlyScreen> createState() => _MonthlyScreenState();
}

class _MonthlyScreenState extends ConsumerState<MonthlyScreen>
    with WidgetsBindingObserver {
  final TextEditingController _entryController = TextEditingController();
  final FocusNode _entryFocusNode = FocusNode();

  late DateTime _month;
  late Future<MonthlyLogSnapshot?> _snapshotFuture;
  late Future<TrackerMonthSnapshot> _trackerFuture;
  late int _selectedDay;
  late bool _followingCurrentMonth;
  Timer? _monthRolloverTimer;
  late _MonthlyViewSection _section;
  JournalEntryType _calendarEntryType = JournalEntryType.event;
  bool _saving = false;
  bool _trackerSaving = false;
  bool _reflecting = false;
  String? _entryActionId;
  bool _sectionScopeInitialized = false;
  bool _wasMonthlySectionActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _section = switch (widget.initialSection) {
      JournalMonthlySection.tasks => _MonthlyViewSection.tasks,
      _ => _MonthlyViewSection.calendar,
    };
    final DateTime now = _now();
    final DateTime currentMonth = DateTime(now.year, now.month);
    final DateTime seed = widget.initialMonth ?? now;
    final DateTime requestedMonth = DateTime(seed.year, seed.month);
    _month = _isAfterMonth(requestedMonth, currentMonth)
        ? currentMonth
        : requestedMonth;
    _followingCurrentMonth = _sameMonth(_month, currentMonth);
    _selectedDay = _followingCurrentMonth ? _clampDay(now.day, _month) : 1;
    _snapshotFuture = _loadSnapshotFor(
      _month,
      writable: _followingCurrentMonth,
    );
    _trackerFuture = _loadTrackerMonth(_month);
    _scheduleMonthRollover();
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

    final bool isMonthlySectionActive =
        currentSectionIndex == AppSectionScope.monthlySectionIndex;
    if (_sectionScopeInitialized &&
        isMonthlySectionActive &&
        !_wasMonthlySectionActive) {
      setState(() {
        _trackerFuture = _loadTrackerMonth(_month);
      });
      _restoreComposerFocus();
    }

    _sectionScopeInitialized = true;
    _wasMonthlySectionActive = isMonthlySectionActive;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.initialMonth == null &&
        _followingCurrentMonth) {
      _refreshMonthIfNeeded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _monthRolloverTimer?.cancel();
    _entryController.dispose();
    _entryFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool busy = _saving || _trackerSaving || _entryActionId != null;
    final MaterialLocalizations material = MaterialLocalizations.of(context);

    return DaymarkPageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: busy ? null : () => _selectMonth(-1),
                tooltip: l10n.previousMonth,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: busy ? null : _chooseMonth,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                  ),
                  child: Text(
                    material.formatMonthYear(_month),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ),
              IconButton(
                onPressed: busy || _followingCurrentMonth
                    ? null
                    : () => _selectMonth(1),
                tooltip: l10n.nextMonth,
                icon: const Icon(Icons.chevron_right),
              ),
              if (!_followingCurrentMonth)
                IconButton(
                  onPressed: busy ? null : _goToCurrentMonth,
                  tooltip: l10n.today,
                  icon: const Icon(Icons.today_outlined),
                ),
              if (_followingCurrentMonth &&
                  _section == _MonthlyViewSection.tasks)
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
          if (!_followingCurrentMonth) ...[
            const SizedBox(height: 4),
            Text(
              l10n.monthlyHistoryReadOnly,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_reflecting) ...[
            const SizedBox(height: 8),
            Text(
              l10n.dailyReflectionPrompt,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SegmentedButton<_MonthlyViewSection>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment<_MonthlyViewSection>(
                  value: _MonthlyViewSection.calendar,
                  label: Text(l10n.monthlyCalendar),
                ),
                ButtonSegment<_MonthlyViewSection>(
                  value: _MonthlyViewSection.tasks,
                  label: Text(l10n.monthlyTasks),
                ),
                ButtonSegment<_MonthlyViewSection>(
                  value: _MonthlyViewSection.tracker,
                  label: Text(l10n.monthlyTracker),
                ),
              ],
              selected: <_MonthlyViewSection>{_section},
              onSelectionChanged: busy
                  ? null
                  : (selection) {
                      _entryController.clear();
                      final _MonthlyViewSection nextSection = selection.single;
                      setState(() {
                        _section = nextSection;
                        if (nextSection != _MonthlyViewSection.tasks) {
                          _reflecting = false;
                        }
                      });
                      if (_section == _MonthlyViewSection.tracker) {
                        _entryFocusNode.unfocus();
                      } else {
                        _restoreComposerFocus();
                      }
                    },
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _section == _MonthlyViewSection.tracker
                ? _buildTrackerSection(context, l10n)
                : FutureBuilder<MonthlyLogSnapshot?>(
                    future: _snapshotFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text(l10n.monthlyLogLoadFailed));
                      }
                      return switch (_section) {
                        _MonthlyViewSection.calendar => _buildCalendar(
                          context,
                          l10n,
                          snapshot.data,
                        ),
                        _MonthlyViewSection.tasks => _buildTasks(
                          context,
                          l10n,
                          snapshot.data,
                        ),
                        _MonthlyViewSection.tracker => const SizedBox.shrink(),
                      };
                    },
                  ),
          ),
          const DaymarkNoticeRegion(),
          if (_followingCurrentMonth &&
              _section != _MonthlyViewSection.tracker &&
              !_reflecting) ...[
            const SizedBox(height: 12),
            _buildComposer(l10n),
          ],
        ],
      ),
    );
  }

  Widget _buildTrackerSection(BuildContext context, AppLocalizations l10n) {
    return FutureBuilder<TrackerMonthSnapshot>(
      future: _trackerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(child: Text(l10n.trackerLoadFailed));
        }

        final int maxSelectableDay = _followingCurrentMonth
            ? _clampDay(_now().day, _month)
            : _daysInMonth(_month);
        final int selectedDay = _selectedDay.clamp(1, maxSelectableDay);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (_followingCurrentMonth) ...<Widget>[
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: _trackerSaving ? null : _createTracker,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.trackerCreate),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Expanded(
              child: TrackerMonthView(
                snapshot: snapshot.requireData,
                selectedDay: selectedDay,
                maxSelectableDay: maxSelectableDay,
                writable: _followingCurrentMonth && !_trackerSaving,
                onSelectedDayChanged: (int day) {
                  setState(() => _selectedDay = day);
                },
                onSetMark: _setTrackerMark,
                onEndEarly: _endTrackerEarly,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCalendar(
    BuildContext context,
    AppLocalizations l10n,
    MonthlyLogSnapshot? snapshot,
  ) {
    final MaterialLocalizations material = MaterialLocalizations.of(context);
    final int dayCount = _daysInMonth(_month);
    final List<MonthlyLogEntry> calendarEntries =
        snapshot?.calendarEntries ?? const <MonthlyLogEntry>[];
    final DateTime today = _dateOnly(_now());

    return ListView.builder(
      itemCount: dayCount,
      itemBuilder: (context, index) {
        final int dayNumber = index + 1;
        final DateTime date = DateTime(_month.year, _month.month, dayNumber);
        final String methodDate = _formatMethodDate(date);
        final List<MonthlyLogEntry> entries = <MonthlyLogEntry>[
          for (final MonthlyLogEntry entry in calendarEntries)
            if (entry.calendarDate == methodDate) entry,
        ];
        final String weekday = material.narrowWeekdays[date.weekday % 7];
        final bool canOpenDaily = !date.isAfter(today);
        final Widget dayLabel = Text(
          '$dayNumber $weekday',
          style: Theme.of(context).textTheme.bodyMedium,
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 52,
                child: canOpenDaily
                    ? InkWell(
                        onTap: () => _openDailyForDate(date),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: dayLabel,
                        ),
                      )
                    : dayLabel,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final MonthlyLogEntry entry in entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _buildCalendarEntryRow(context, l10n, entry),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCalendarEntryRow(
    BuildContext context,
    AppLocalizations l10n,
    MonthlyLogEntry entry,
  ) {
    final bool actionInProgress = _entryActionId == entry.id;
    final bool openTask =
        entry.type == JournalEntryType.task &&
        entry.taskState == JournalTaskState.open;
    final TextStyle? entryStyle = Theme.of(context).textTheme.bodyLarge;
    final Widget marker = actionInProgress
        ? const Center(
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : Text(
            _monthlyCalendarEntrySymbol(entry),
            textAlign: TextAlign.center,
            style: entry.taskState == JournalTaskState.discarded
                ? Theme.of(context).textTheme.titleMedium
                      ?.copyWith(decoration: TextDecoration.lineThrough)
                : Theme.of(context).textTheme.titleMedium,
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
    if (!_followingCurrentMonth || actionInProgress) {
      return row;
    }
    return SizedBox(
      width: double.infinity,
      child: PopupMenuButton<_MonthlyEntryAction>(
        enabled: _entryActionId == null,
        tooltip: l10n.entryActions,
        padding: EdgeInsets.zero,
        onSelected: (action) {
          unawaited(_applyEntryAction(entry, action));
        },
        itemBuilder: (context) => [
          if (openTask)
            PopupMenuItem(
              value: _MonthlyEntryAction.complete,
              child: Text(l10n.completeTask),
            ),
          if (openTask)
            PopupMenuItem(
              value: _MonthlyEntryAction.migrate,
              child: Text(l10n.migrateTask),
            ),
          if (openTask)
            PopupMenuItem(
              value: _MonthlyEntryAction.schedule,
              child: Text(l10n.scheduleTask),
            ),
          PopupMenuItem(
            value: _MonthlyEntryAction.reference,
            child: Text(l10n.referenceEntry),
          ),
          PopupMenuItem(
            value: _MonthlyEntryAction.signifiers,
            child: Text(l10n.signifiers),
          ),
          if (openTask)
            PopupMenuItem(
              value: _MonthlyEntryAction.discard,
              child: Text(l10n.discardTask),
            ),
        ],
        child: row,
      ),
    );
  }

  Widget _buildTasks(
    BuildContext context,
    AppLocalizations l10n,
    MonthlyLogSnapshot? snapshot,
  ) {
    final List<MonthlyLogEntry> allTaskEntries =
        snapshot?.taskEntries ?? const <MonthlyLogEntry>[];
    final List<MonthlyLogEntry> taskEntries = _reflecting
        ? <MonthlyLogEntry>[
            for (final MonthlyLogEntry entry in allTaskEntries)
              if (entry.type == JournalEntryType.task &&
                  entry.taskState == JournalTaskState.open)
                entry,
          ]
        : allTaskEntries;
    if (taskEntries.isEmpty) {
      return DaymarkEmptyState(
        message: _reflecting
            ? l10n.dailyReflectionEmpty
            : l10n.emptyMonthlyTasks,
        topPadding: 16,
      );
    }

    return ListView.separated(
      itemCount: taskEntries.length,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final MonthlyLogEntry entry = taskEntries[index];
        final TextStyle? entryStyle = Theme.of(context).textTheme.bodyLarge;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: _buildTaskRow(context, l10n, entry, entryStyle),
        );
      },
    );
  }

  Widget _buildTaskRow(
    BuildContext context,
    AppLocalizations l10n,
    MonthlyLogEntry entry,
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
            _taskSymbol(entry.taskState),
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
    if (!_followingCurrentMonth || actionInProgress) return row;

    final bool openTask =
        entry.type == JournalEntryType.task &&
        entry.taskState == JournalTaskState.open;
    return SizedBox(
      width: double.infinity,
      child: PopupMenuButton<_MonthlyEntryAction>(
        enabled: _entryActionId == null,
        tooltip: l10n.entryActions,
        padding: EdgeInsets.zero,
        onSelected: (action) {
          unawaited(_applyEntryAction(entry, action));
        },
        itemBuilder: (context) => [
          if (openTask)
            PopupMenuItem(
              value: _MonthlyEntryAction.complete,
              child: Text(l10n.completeTask),
            ),
          if (openTask)
            PopupMenuItem(
              value: _MonthlyEntryAction.migrate,
              child: Text(l10n.migrateTask),
            ),
          if (openTask)
            PopupMenuItem(
              value: _MonthlyEntryAction.schedule,
              child: Text(l10n.scheduleTask),
            ),
          if (!_reflecting)
            PopupMenuItem(
              value: _MonthlyEntryAction.reference,
              child: Text(l10n.referenceEntry),
            ),
          if (!_reflecting)
            PopupMenuItem(
              value: _MonthlyEntryAction.signifiers,
              child: Text(l10n.signifiers),
            ),
          if (openTask)
            PopupMenuItem(
              value: _MonthlyEntryAction.discard,
              child: Text(l10n.discardTask),
            ),
        ],
        child: row,
      ),
    );
  }

  Widget _buildComposer(AppLocalizations l10n) {
    final bool calendar = _section == _MonthlyViewSection.calendar;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (calendar) ...[
          DaymarkDropdownButton<int>(
            value: _selectedDay,
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _selectedDay = value);
                      _restoreComposerFocus();
                    }
                  },
            items: [
              for (int day = 1; day <= _daysInMonth(_month); day++)
                DropdownMenuItem<int>(value: day, child: Text('$day')),
            ],
          ),
          const SizedBox(width: 12),
          DaymarkDropdownButton<JournalEntryType>(
            value: _calendarEntryType,
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _calendarEntryType = value);
                      _restoreComposerFocus();
                    }
                  },
            items: [
              DropdownMenuItem(
                value: JournalEntryType.event,
                child: Text(l10n.entryEvent),
              ),
              DropdownMenuItem(
                value: JournalEntryType.task,
                child: Text(l10n.entryTask),
              ),
            ],
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Focus(
            onKeyEvent: _handleComposerKeyEvent,
            child: TextField(
              controller: _entryController,
              focusNode: _entryFocusNode,
              autofocus:
                  defaultTargetPlatform == TargetPlatform.linux &&
                  _followingCurrentMonth,
              enabled: !_saving,
              minLines: 1,
              maxLines: 4,
              onChanged: (_) => JournalActivityGuard.recordActivity(context),
              decoration: InputDecoration(
                hintText: calendar
                    ? (_calendarEntryType == JournalEntryType.task
                          ? l10n.monthlyCalendarTaskHint
                          : l10n.monthlyEventHint)
                    : l10n.monthlyTaskHint,
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

  KeyEventResult _handleComposerKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isControlPressed) {
      unawaited(_capture());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _restoreComposerFocus() {
    if (defaultTargetPlatform != TargetPlatform.linux ||
        !_followingCurrentMonth ||
        _section == _MonthlyViewSection.tracker ||
        _reflecting ||
        _saving ||
        _entryActionId != null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _followingCurrentMonth &&
          _section != _MonthlyViewSection.tracker &&
          !_reflecting &&
          !_saving &&
          _entryActionId == null) {
        _entryFocusNode.requestFocus();
      }
    });
  }

  MonthlyJournalDataSource _dataSource() {
    return ref.read(monthlyJournalDataSourceProvider);
  }

  TrackerDataSource _trackerDataSource() {
    return ref.read(trackerDataSourceProvider);
  }

  Future<MonthlyLogSnapshot?> _loadSnapshotFor(
    DateTime month, {
    required bool writable,
  }) {
    final String periodStart = formatJournalMonthStart(month);
    final MonthlyJournalDataSource dataSource = _dataSource();
    return writable
        ? dataSource.load(periodStart)
        : dataSource.find(periodStart);
  }

  Future<TrackerMonthSnapshot> _loadTrackerMonth(DateTime month) {
    return _trackerDataSource().loadMonth(formatJournalMonthStart(month));
  }

  Future<void> _selectMonth(int offset) {
    return _moveToMonth(DateTime(_month.year, _month.month + offset));
  }

  Future<void> _chooseMonth() async {
    if (_saving || _trackerSaving || _entryActionId != null) {
      return;
    }
    final DateTime today = _dateOnly(_now());
    final DateTime initialDate = _sameMonth(_month, _currentMonth())
        ? today
        : DateTime(_month.year, _month.month, 1);
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: today,
      initialEntryMode: DatePickerEntryMode.calendar,
      initialDatePickerMode: DatePickerMode.year,
    );
    if (!mounted || selected == null) {
      return;
    }
    await _moveToMonth(DateTime(selected.year, selected.month));
  }

  Future<void> _goToCurrentMonth() {
    return _moveToMonth(_currentMonth());
  }

  Future<void> _moveToMonth(DateTime target) async {
    if (_saving || _trackerSaving || _entryActionId != null) {
      return;
    }
    final DateTime currentMonth = _currentMonth();
    if (_isAfterMonth(target, currentMonth)) {
      return;
    }
    final bool followingCurrentMonth = _sameMonth(target, currentMonth);
    final DateTime now = _now();

    _monthRolloverTimer?.cancel();
    _entryController.clear();
    setState(() {
      _month = target;
      _followingCurrentMonth = followingCurrentMonth;
      _reflecting = false;
      _selectedDay = followingCurrentMonth ? _clampDay(now.day, target) : 1;
      _snapshotFuture = _loadSnapshotFor(
        target,
        writable: followingCurrentMonth,
      );
      _trackerFuture = _loadTrackerMonth(target);
    });
    _scheduleMonthRollover();
    if (followingCurrentMonth) {
      _restoreComposerFocus();
    }
  }

  void _openDailyForDate(DateTime date) {
    final DateTime target = _dateOnly(date);
    final DateTime today = _dateOnly(_now());
    if (target.isAfter(today)) {
      return;
    }
    if (target == today) {
      context.go('/');
      return;
    }
    context.go('/daily/${_formatMethodDate(target)}');
  }

  Future<void> _capture() async {
    final String content = _entryController.text.trim();
    if (content.isEmpty ||
        _saving ||
        _reflecting ||
        !_followingCurrentMonth ||
        _section == _MonthlyViewSection.tracker) {
      return;
    }

    final JournalMonthlySection section =
        _section == _MonthlyViewSection.calendar
        ? JournalMonthlySection.calendar
        : JournalMonthlySection.tasks;
    final DateTime month = _month;
    final int selectedDay = _selectedDay;
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _saving = true);

    try {
      final MonthlyJournalDataSource dataSource = _dataSource();
      final MonthlyLogSnapshot? snapshot = await _snapshotFuture;
      if (snapshot == null) {
        throw StateError('Current Monthly Log is missing.');
      }
      final Set<String> beforeEntryIds = <String>{
        for (final MonthlyLogEntry entry in snapshot.calendarEntries) entry.id,
        for (final MonthlyLogEntry entry in snapshot.taskEntries) entry.id,
      };
      if (section == JournalMonthlySection.calendar) {
        final String calendarDate = _formatMethodDate(
          DateTime(month.year, month.month, selectedDay),
        );
        if (_calendarEntryType == JournalEntryType.task) {
          await ref
              .read(monthlyCalendarTaskDataSourceProvider)
              .capture(
                logId: snapshot.logId,
                calendarDate: calendarDate,
                content: content,
              );
        } else {
          await dataSource.captureCalendarEvent(
            logId: snapshot.logId,
            calendarDate: calendarDate,
            content: content,
          );
        }
      } else {
        await dataSource.captureTask(logId: snapshot.logId, content: content);
      }
      final MonthlyLogSnapshot updatedSnapshot = await dataSource.load(
        formatJournalMonthStart(_month),
      );
      final List<String> capturedEntryIds = <String>[
        for (final MonthlyLogEntry entry in updatedSnapshot.calendarEntries)
          if (!beforeEntryIds.contains(entry.id)) entry.id,
        for (final MonthlyLogEntry entry in updatedSnapshot.taskEntries)
          if (!beforeEntryIds.contains(entry.id)) entry.id,
      ];

      if (!mounted) return;
      _entryController.clear();
      setState(() {
        _snapshotFuture = Future<MonthlyLogSnapshot?>.value(updatedSnapshot);
        _saving = false;
      });
      if (capturedEntryIds.length == 1) {
        _showCaptureUndo(capturedEntryIds.single);
      }
      _restoreComposerFocus();
    } catch (error, stackTrace) {
      _reportUnexpectedMonthlyError('capture', error, stackTrace);
      if (!mounted) {
        return;
      }
      ref.read(daymarkNoticeProvider.notifier).showError(l10n.saveEntryFailed);
      setState(() => _saving = false);
    }
  }

  Future<void> _createTracker() async {
    if (_trackerSaving || !_followingCurrentMonth) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DateTime now = _now();
    final TrackerDraft? draft = await showTrackerCreateDialog(
      context: context,
      today: DateTime(now.year, now.month, now.day),
    );
    if (!mounted || draft == null) return;

    setState(() => _trackerSaving = true);
    try {
      await _trackerDataSource().create(
        title: draft.title,
        startDate: _formatMethodDate(draft.startDate),
        plannedEndDate: _formatMethodDate(draft.plannedEndDate),
      );
      if (!mounted) return;
      setState(() {
        _trackerFuture = _loadTrackerMonth(_month);
        _trackerSaving = false;
      });
      ref.read(daymarkNoticeProvider.notifier).showInfo(l10n.trackerCreated);
    } catch (error, stackTrace) {
      _reportUnexpectedMonthlyError('create tracker', error, stackTrace);
      if (!mounted) return;
      setState(() => _trackerSaving = false);
      ref
          .read(daymarkNoticeProvider.notifier)
          .showError(l10n.trackerCreateFailed);
    }
  }

  Future<void> _setTrackerMark(TrackerRecord tracker, int? value) async {
    if (_trackerSaving || !_followingCurrentMonth) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String methodDate = _formatMethodDate(
      DateTime(_month.year, _month.month, _selectedDay),
    );
    setState(() => _trackerSaving = true);
    try {
      await _trackerDataSource().setMark(
        trackerId: tracker.id,
        methodDate: methodDate,
        value: value,
      );
      if (!mounted) return;
      setState(() {
        _trackerFuture = _loadTrackerMonth(_month);
        _trackerSaving = false;
      });
    } catch (error, stackTrace) {
      _reportUnexpectedMonthlyError('update tracker mark', error, stackTrace);
      if (!mounted) return;
      setState(() => _trackerSaving = false);
      ref
          .read(daymarkNoticeProvider.notifier)
          .showError(l10n.trackerUpdateFailed);
    }
  }

  Future<void> _endTrackerEarly(TrackerRecord tracker) async {
    if (_trackerSaving || !_followingCurrentMonth) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(l10n.trackerEndConfirmTitle),
            content: Text(l10n.trackerEndConfirmMessage),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(
                  MaterialLocalizations.of(context).cancelButtonLabel,
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.trackerEndConfirm),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !confirmed) return;

    final String methodDate = _formatMethodDate(
      DateTime(_month.year, _month.month, _selectedDay),
    );
    setState(() => _trackerSaving = true);
    try {
      await _trackerDataSource().endEarly(
        trackerId: tracker.id,
        methodDate: methodDate,
      );
      if (!mounted) return;
      setState(() {
        _trackerFuture = _loadTrackerMonth(_month);
        _trackerSaving = false;
      });
      ref.read(daymarkNoticeProvider.notifier).showInfo(l10n.trackerEnded);
    } catch (error, stackTrace) {
      _reportUnexpectedMonthlyError('end tracker', error, stackTrace);
      if (!mounted) return;
      setState(() => _trackerSaving = false);
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
        _snapshotFuture = _loadSnapshotFor(
          _month,
          writable: _followingCurrentMonth,
        );
      });
      _restoreComposerFocus();
    } catch (error, stackTrace) {
      _reportUnexpectedMonthlyError('capture undo', error, stackTrace);
      if (!mounted) return;
      ref
          .read(daymarkNoticeProvider.notifier)
          .showError(AppLocalizations.of(context).undoCaptureFailed);
    }
  }

  Future<void> _applyEntryAction(
    MonthlyLogEntry entry,
    _MonthlyEntryAction action,
  ) async {
    if (_entryActionId != null || !_followingCurrentMonth) {
      return;
    }
    if (_reflecting &&
        (action == _MonthlyEntryAction.reference ||
            action == _MonthlyEntryAction.signifiers)) {
      return;
    }
    final bool openTask =
        entry.type == JournalEntryType.task &&
        entry.taskState == JournalTaskState.open;
    if (action != _MonthlyEntryAction.reference &&
        action != _MonthlyEntryAction.signifiers &&
        !openTask) {
      return;
    }
    if (action == _MonthlyEntryAction.signifiers) {
      try {
        await showEntrySignifierDialog(
          context: context,
          ref: ref,
          entryId: entry.id,
        );
      } catch (error, stackTrace) {
        _reportUnexpectedMonthlyError('signifiers', error, stackTrace);
        if (mounted) {
          ref
              .read(daymarkNoticeProvider.notifier)
              .showError(AppLocalizations.of(context).signifierUpdateFailed);
        }
      }
      return;
    }

    final DateTime actionMonth = _month;
    final DateTime actionDate = _dateOnly(_now());
    String? migrationMethodDate;
    String? migrationMonthStart;
    String? migrationCollectionId;
    if (action == _MonthlyEntryAction.migrate) {
      final TaskMigrationDestination? destination =
          await showTaskMigrationDestinationDialog(
            context: context,
            includeNextMonth: true,
          );
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
          migrationMonthStart = nextTaskMigrationMonthStart(actionMonth);
          break;
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
    if (action == _MonthlyEntryAction.reference) {
      referenceCollectionId = await showEntryCollectionReferenceDialog(
        context: context,
        dataSource: ref.read(entryCollectionReferenceDataSourceProvider),
      );
      if (!mounted || referenceCollectionId == null) {
        return;
      }
    }

    String? schedulePeriodStart;
    if (action == _MonthlyEntryAction.schedule) {
      schedulePeriodStart = await showTaskScheduleDialog(
        context: context,
        anchor: actionMonth,
      );
      if (!mounted || schedulePeriodStart == null) {
        return;
      }
    }

    ref.read(daymarkNoticeProvider.notifier).dismiss();
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _entryActionId = entry.id);

    try {
      final MonthlyJournalDataSource dataSource = _dataSource();
      switch (action) {
        case _MonthlyEntryAction.complete:
          await dataSource.completeTask(entryId: entry.id);
          break;
        case _MonthlyEntryAction.migrate:
          if (migrationMethodDate != null) {
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
          break;
        case _MonthlyEntryAction.schedule:
          await dataSource.scheduleTaskToFuture(
            entryId: entry.id,
            periodStart: schedulePeriodStart!,
          );
          break;
        case _MonthlyEntryAction.reference:
          await ref
              .read(entryCollectionReferenceDataSourceProvider)
              .referenceEntry(
                entryId: entry.id,
                collectionId: referenceCollectionId!,
              );
          break;
        case _MonthlyEntryAction.discard:
          await dataSource.discardTask(entryId: entry.id);
          break;
        case _MonthlyEntryAction.signifiers:
          break;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _snapshotFuture = dataSource.load(formatJournalMonthStart(_month));
        _entryActionId = null;
      });
    } catch (error, stackTrace) {
      _reportUnexpectedMonthlyError(
        action == _MonthlyEntryAction.reference
            ? 'collection reference'
            : 'task action',
        error,
        stackTrace,
      );
      if (!mounted) {
        return;
      }
      final String message = action == _MonthlyEntryAction.reference
          ? l10n.referenceEntryFailed
          : l10n.taskActionFailed;
      ref.read(daymarkNoticeProvider.notifier).showError(message);
      setState(() => _entryActionId = null);
    }
  }

  void _toggleReflection() {
    if (_saving ||
        _trackerSaving ||
        _entryActionId != null ||
        !_followingCurrentMonth ||
        _section != _MonthlyViewSection.tasks) {
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

  Future<void> _lock() async {
    try {
      await ref.read(journalSessionControllerProvider.notifier).lock();
    } catch (error, stackTrace) {
      _reportUnexpectedMonthlyError('lock', error, stackTrace);
    }
  }

  void _refreshMonthIfNeeded() {
    if (!_followingCurrentMonth) {
      return;
    }
    final DateTime now = _now();
    final DateTime currentMonth = DateTime(now.year, now.month);
    if (_sameMonth(currentMonth, _month)) {
      setState(() {
        _trackerFuture = _loadTrackerMonth(_month);
      });
      _scheduleMonthRollover();
      return;
    }

    setState(() {
      _month = currentMonth;
      _reflecting = false;
      _selectedDay = _clampDay(now.day, _month);
      _snapshotFuture = _loadSnapshotFor(_month, writable: true);
      _trackerFuture = _loadTrackerMonth(_month);
    });
    _scheduleMonthRollover();
  }

  void _scheduleMonthRollover() {
    _monthRolloverTimer?.cancel();
    if (widget.initialMonth != null || !_followingCurrentMonth) {
      return;
    }

    final DateTime now = _now();
    final DateTime nextMonth = DateTime(now.year, now.month + 1);
    _monthRolloverTimer = Timer(
      nextMonth.difference(now) + const Duration(seconds: 1),
      _refreshMonthIfNeeded,
    );
  }

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  DateTime _currentMonth() {
    final DateTime now = _now();
    return DateTime(now.year, now.month);
  }
}

enum _MonthlyViewSection { calendar, tasks, tracker }

enum _MonthlyEntryAction {
  complete,
  migrate,
  schedule,
  reference,
  signifiers,
  discard,
}

int _daysInMonth(DateTime month) {
  return DateTime(month.year, month.month + 1, 0).day;
}

int _clampDay(int day, DateTime month) {
  final int lastDay = _daysInMonth(month);
  if (day < 1) {
    return 1;
  }
  if (day > lastDay) {
    return lastDay;
  }
  return day;
}

bool _sameMonth(DateTime left, DateTime right) {
  return left.year == right.year && left.month == right.month;
}

bool _isAfterMonth(DateTime left, DateTime right) {
  return left.year > right.year ||
      (left.year == right.year && left.month > right.month);
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _formatMethodDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

String _monthlyCalendarEntrySymbol(MonthlyLogEntry entry) =>
    switch (entry.type) {
      JournalEntryType.task => _taskSymbol(entry.taskState),
      JournalEntryType.event => '○',
      JournalEntryType.note => '–',
    };

String _taskSymbol(JournalTaskState? state) => switch (state) {
  JournalTaskState.completed => '×',
  JournalTaskState.migrated => '>',
  JournalTaskState.scheduled => '<',
  JournalTaskState.discarded => '•',
  JournalTaskState.open => '•',
  null => '•',
};

void _reportUnexpectedMonthlyError(
  String operation,
  Object error,
  StackTrace stackTrace,
) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: FlutterError(
        'Monthly journal $operation failed (${error.runtimeType}).',
      ),
      stack: stackTrace,
      library: 'daymark',
    ),
  );
}
