import 'dart:async';

import 'package:daymark/core/session/journal_future_history_session.dart';
import 'package:daymark/core/session/journal_session.dart';
import 'package:daymark/core/session/journal_session_controller.dart';
import 'package:daymark/features/journal/data/future_log_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:daymark/presentation/app_section_scope.dart';
import 'package:daymark/presentation/daymark_controls.dart';
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

abstract interface class FutureJournalDataSource {
  Future<FutureLogSnapshot> load(String periodStart);

  Future<FutureLogSnapshot?> find(String periodStart);

  Future<void> capture({
    required String logId,
    required JournalEntryType type,
    required String content,
  });

  Future<void> completeTask({required String entryId});

  Future<void> discardTask({required String entryId});
}

final Provider<FutureJournalDataSource> futureJournalDataSourceProvider =
    Provider<FutureJournalDataSource>((ref) {
      final JournalAccessState access = ref
          .watch(journalSessionControllerProvider)
          .requireValue;
      if (access case JournalUnlocked(:final session)) {
        return _SessionFutureJournalDataSource(session);
      }
      throw StateError('Future requires an unlocked journal session.');
    });

final class _SessionFutureJournalDataSource implements FutureJournalDataSource {
  const _SessionFutureJournalDataSource(this._session);

  final JournalSession _session;

  @override
  Future<FutureLogSnapshot> load(String periodStart) {
    return _session.loadFutureLog(periodStart);
  }

  @override
  Future<FutureLogSnapshot?> find(String periodStart) {
    return _session.findFutureLog(periodStart);
  }

  @override
  Future<void> capture({
    required String logId,
    required JournalEntryType type,
    required String content,
  }) {
    return _session.captureFutureLogEntry(
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
  Future<void> discardTask({required String entryId}) {
    return _session.discardTask(entryId: entryId);
  }
}

class FutureScreen extends ConsumerStatefulWidget {
  const FutureScreen({this.initialDate, super.key});

  final DateTime? initialDate;

  @override
  ConsumerState<FutureScreen> createState() => _FutureScreenState();
}

class _FutureScreenState extends ConsumerState<FutureScreen>
    with WidgetsBindingObserver {
  static const int _visibleMonthCount = 6;

  final TextEditingController _entryController = TextEditingController();
  final FocusNode _entryFocusNode = FocusNode();

  late DateTime _anchorMonth;
  late List<DateTime> _months;
  late DateTime _selectedMonth;
  late Future<List<FutureLogSnapshot>> _snapshotsFuture;
  late Future<FutureLogSnapshot?> _arrivedSnapshotFuture;
  Timer? _horizonRolloverTimer;
  JournalEntryType _entryType = JournalEntryType.task;
  bool _saving = false;
  String? _entryActionId;
  bool _sectionScopeInitialized = false;
  bool _wasFutureSectionActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final DateTime seed = widget.initialDate ?? DateTime.now();
    _anchorMonth = DateTime(seed.year, seed.month);
    _months = _futureMonths(_anchorMonth);
    _selectedMonth = _months.first;
    _snapshotsFuture = _loadSnapshots();
    _arrivedSnapshotFuture = _loadArrivedSnapshot();
    _scheduleHorizonRollover();
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

    final bool isFutureSectionActive =
        currentSectionIndex == AppSectionScope.futureSectionIndex;
    if (_sectionScopeInitialized &&
        isFutureSectionActive &&
        !_wasFutureSectionActive) {
      _snapshotsFuture = _loadSnapshots();
      _arrivedSnapshotFuture = _loadArrivedSnapshot();
      _restoreComposerFocus();
    }
    _sectionScopeInitialized = true;
    _wasFutureSectionActive = isFutureSectionActive;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.initialDate == null) {
      _refreshHorizonIfNeeded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _horizonRolloverTimer?.cancel();
    _entryController.dispose();
    _entryFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return DaymarkPageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.future,
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
          FutureBuilder<FutureLogSnapshot?>(
            future: _arrivedSnapshotFuture,
            builder: (context, snapshot) {
              final FutureLogSnapshot? arrived = snapshot.data;
              final bool hasReviewableEntries =
                  arrived?.entries.any(
                    (entry) =>
                        (entry.type == JournalEntryType.task &&
                            entry.taskState == JournalTaskState.open) ||
                        (entry.type == JournalEntryType.event &&
                            !entry.hasOutgoingMigration),
                  ) ??
                  false;
              if (!hasReviewableEntries) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey<String>('review-arrived-future'),
                    onPressed: () =>
                        context.go('/future/${arrived!.periodStart}'),
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
              future: _snapshotsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return Center(child: Text(l10n.futureLogLoadFailed));
                }
                return _buildOverview(context, l10n, snapshot.requireData);
              },
            ),
          ),
          const DaymarkNoticeRegion(),
          const SizedBox(height: 12),
          _buildComposer(context, l10n),
        ],
      ),
    );
  }

  Widget _buildOverview(
    BuildContext context,
    AppLocalizations l10n,
    List<FutureLogSnapshot> snapshots,
  ) {
    return ListView.builder(
      itemCount: _months.length,
      itemBuilder: (context, index) {
        final DateTime month = _months[index];
        final String periodStart = formatFuturePeriodStart(month);
        final FutureLogSnapshot snapshot = snapshots.singleWhere(
          (item) => item.periodStart == periodStart,
        );

        return Padding(
          key: ValueKey<String>('future-$periodStart'),
          padding: EdgeInsets.only(
            bottom: index == _months.length - 1 ? 0 : 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                MaterialLocalizations.of(context).formatMonthYear(month),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              if (snapshot.entries.isEmpty)
                Text(
                  l10n.emptyFutureMonth,
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else
                for (final FutureLogEntry entry in snapshot.entries)
                  _buildEntry(context, l10n, entry),
              if (index != _months.length - 1) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildEntry(
    BuildContext context,
    AppLocalizations l10n,
    FutureLogEntry entry,
  ) {
    final TextStyle? entryStyle = Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _buildEntryRow(context, l10n, entry, entryStyle),
    );
  }

  Widget _buildEntryRow(
    BuildContext context,
    AppLocalizations l10n,
    FutureLogEntry entry,
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
      child: PopupMenuButton<_FutureEntryAction>(
        enabled: _entryActionId == null,
        tooltip: l10n.entryActions,
        padding: EdgeInsets.zero,
        onSelected: (action) {
          unawaited(_applyEntryAction(entry, action));
        },
        itemBuilder: (context) => [
          if (openTask)
            PopupMenuItem(
              value: _FutureEntryAction.complete,
              child: Text(l10n.completeTask),
            ),
          PopupMenuItem(
            value: _FutureEntryAction.reference,
            child: Text(l10n.referenceEntry),
          ),
          PopupMenuItem(
            value: _FutureEntryAction.signifiers,
            child: Text(l10n.signifiers),
          ),
          if (openTask)
            PopupMenuItem(
              value: _FutureEntryAction.discard,
              child: Text(l10n.discardTask),
            ),
        ],
        child: row,
      ),
    );
  }

  Widget _buildComposer(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DaymarkDropdownButton<DateTime>(
                dropdownKey: const ValueKey<String>('future-month-target'),
                value: _selectedMonth,
                isExpanded: true,
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _selectedMonth = value);
                          _restoreComposerFocus();
                        }
                      },
                items: [
                  for (final DateTime month in _months)
                    DropdownMenuItem<DateTime>(
                      value: month,
                      child: Text(
                        MaterialLocalizations.of(context)
                            .formatMonthYear(month),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            DaymarkDropdownButton<JournalEntryType>(
              dropdownKey: const ValueKey<String>('future-entry-type'),
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
                DropdownMenuItem<JournalEntryType>(
                  value: JournalEntryType.task,
                  child: Text(l10n.entryTask),
                ),
                DropdownMenuItem<JournalEntryType>(
                  value: JournalEntryType.event,
                  child: Text(l10n.entryEvent),
                ),
                DropdownMenuItem<JournalEntryType>(
                  value: JournalEntryType.note,
                  child: Text(l10n.entryNote),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
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
                  onChanged: (_) =>
                      JournalActivityGuard.recordActivity(context),
                  decoration: InputDecoration(
                    hintText: l10n.futureEntryHint,
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
        _saving ||
        _entryActionId != null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_saving && _entryActionId == null) {
        _entryFocusNode.requestFocus();
      }
    });
  }

  FutureJournalDataSource _dataSource() {
    return ref.read(futureJournalDataSourceProvider);
  }

  Future<List<FutureLogSnapshot>> _loadSnapshots() {
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
    final RapidLogInput rapidLog = parseRapidLogInput(
      _entryController.text,
      fallbackType: _entryType,
    );
    if (rapidLog.content.isEmpty || _saving) {
      return;
    }

    final DateTime selectedMonth = _selectedMonth;
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _saving = true);

    try {
      final FutureJournalDataSource dataSource = _dataSource();
      final List<FutureLogSnapshot> snapshots = await _snapshotsFuture;
      final String periodStart = formatFuturePeriodStart(selectedMonth);
      final FutureLogSnapshot target = snapshots.singleWhere(
        (snapshot) => snapshot.periodStart == periodStart,
      );

      final Set<String> beforeEntryIds = <String>{
        for (final FutureLogEntry entry in target.entries) entry.id,
      };
      await dataSource.capture(
        logId: target.logId,
        type: rapidLog.type,
        content: rapidLog.content,
      );
      final List<FutureLogSnapshot> updatedSnapshots = await _loadSnapshots();
      final FutureLogSnapshot updatedTarget = updatedSnapshots.singleWhere(
        (snapshot) => snapshot.periodStart == periodStart,
      );
      final List<String> capturedEntryIds = <String>[
        for (final FutureLogEntry entry in updatedTarget.entries)
          if (!beforeEntryIds.contains(entry.id)) entry.id,
      ];

      if (!mounted) return;
      _entryController.clear();
      setState(() {
        _snapshotsFuture = Future<List<FutureLogSnapshot>>.value(
          updatedSnapshots,
        );
        _saving = false;
      });
      if (capturedEntryIds.length == 1) {
        _showCaptureUndo(capturedEntryIds.single);
      }
      _restoreComposerFocus();
    } catch (error, stackTrace) {
      _reportUnexpectedFutureError('capture', error, stackTrace);
      if (!mounted) {
        return;
      }
      ref.read(daymarkNoticeProvider.notifier).showError(l10n.saveEntryFailed);
      setState(() => _saving = false);
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
        _snapshotsFuture = _loadSnapshots();
      });
      _restoreComposerFocus();
    } catch (error, stackTrace) {
      _reportUnexpectedFutureError('capture undo', error, stackTrace);
      if (!mounted) return;
      ref
          .read(daymarkNoticeProvider.notifier)
          .showError(AppLocalizations.of(context).undoCaptureFailed);
    }
  }

  Future<void> _applyEntryAction(
    FutureLogEntry entry,
    _FutureEntryAction action,
  ) async {
    if (_entryActionId != null) {
      return;
    }
    final bool openTask =
        entry.type == JournalEntryType.task &&
        entry.taskState == JournalTaskState.open;
    if (action != _FutureEntryAction.reference &&
        action != _FutureEntryAction.signifiers &&
        !openTask) {
      return;
    }
    if (action == _FutureEntryAction.signifiers) {
      try {
        await showEntrySignifierDialog(
          context: context,
          ref: ref,
          entryId: entry.id,
        );
      } catch (error, stackTrace) {
        _reportUnexpectedFutureError('signifiers', error, stackTrace);
        if (mounted) {
          ref
              .read(daymarkNoticeProvider.notifier)
              .showError(AppLocalizations.of(context).signifierUpdateFailed);
        }
      }
      return;
    }

    String? referenceCollectionId;
    if (action == _FutureEntryAction.reference) {
      referenceCollectionId = await showEntryCollectionReferenceDialog(
        context: context,
        dataSource: ref.read(entryCollectionReferenceDataSourceProvider),
      );
      if (!mounted || referenceCollectionId == null) {
        return;
      }
    }

    // Any deliberate journal action supersedes the short-lived capture Undo.
    ref.read(daymarkNoticeProvider.notifier).dismiss();
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _entryActionId = entry.id);

    try {
      final FutureJournalDataSource dataSource = _dataSource();
      switch (action) {
        case _FutureEntryAction.complete:
          await dataSource.completeTask(entryId: entry.id);
          break;
        case _FutureEntryAction.reference:
          await ref
              .read(entryCollectionReferenceDataSourceProvider)
              .referenceEntry(
                entryId: entry.id,
                collectionId: referenceCollectionId!,
              );
          break;
        case _FutureEntryAction.discard:
          await dataSource.discardTask(entryId: entry.id);
          break;
        case _FutureEntryAction.signifiers:
          break;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _snapshotsFuture = _loadSnapshots();
        _entryActionId = null;
      });
    } catch (error, stackTrace) {
      _reportUnexpectedFutureError(
        action == _FutureEntryAction.reference
            ? 'collection reference'
            : 'task action',
        error,
        stackTrace,
      );
      if (!mounted) {
        return;
      }
      final String message = action == _FutureEntryAction.reference
          ? l10n.referenceEntryFailed
          : l10n.taskActionFailed;
      ref.read(daymarkNoticeProvider.notifier).showError(message);
      setState(() => _entryActionId = null);
    }
  }

  Future<void> _lock() async {
    try {
      await ref.read(journalSessionControllerProvider.notifier).lock();
    } catch (error, stackTrace) {
      _reportUnexpectedFutureError('lock', error, stackTrace);
    }
  }

  void _refreshHorizonIfNeeded() {
    final DateTime now = DateTime.now();
    final DateTime currentMonth = DateTime(now.year, now.month);
    if (currentMonth == _anchorMonth) {
      setState(() {
        _arrivedSnapshotFuture = _loadArrivedSnapshot();
      });
      _scheduleHorizonRollover();
      return;
    }

    final String selectedPeriod = formatFuturePeriodStart(_selectedMonth);
    final List<DateTime> months = _futureMonths(currentMonth);
    final int selectedIndex = months.indexWhere(
      (month) => formatFuturePeriodStart(month) == selectedPeriod,
    );

    setState(() {
      _anchorMonth = currentMonth;
      _months = months;
      _selectedMonth = selectedIndex >= 0
          ? months[selectedIndex]
          : months.first;
      _snapshotsFuture = _loadSnapshots();
      _arrivedSnapshotFuture = _loadArrivedSnapshot();
    });
    _scheduleHorizonRollover();
    _restoreComposerFocus();
  }

  void _scheduleHorizonRollover() {
    _horizonRolloverTimer?.cancel();
    if (widget.initialDate != null) {
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime nextMonth = DateTime(now.year, now.month + 1);
    _horizonRolloverTimer = Timer(
      nextMonth.difference(now) + const Duration(seconds: 1),
      _refreshHorizonIfNeeded,
    );
  }

  List<DateTime> _futureMonths(DateTime anchorMonth) {
    return <DateTime>[
      for (int offset = 1; offset <= _visibleMonthCount; offset++)
        DateTime(anchorMonth.year, anchorMonth.month + offset),
    ];
  }
}

enum _FutureEntryAction { complete, reference, signifiers, discard }

String _entrySymbol(FutureLogEntry entry) => switch (entry.type) {
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

void _reportUnexpectedFutureError(
  String operation,
  Object error,
  StackTrace stackTrace,
) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: FlutterError(
        'Future Log $operation failed (${error.runtimeType}).',
      ),
      stack: stackTrace,
      library: 'daymark',
    ),
  );
}
