import 'package:daymark/core/session/journal_daily_history_session.dart';
import 'package:daymark/core/session/journal_session.dart';
import 'package:daymark/core/session/journal_session_controller.dart';
import 'package:daymark/features/journal/data/daily_log_repository.dart';
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

abstract interface class DailyHistoryDataSource {
  Future<DailyLogSnapshot?> find(String methodDate);
}

final Provider<DailyHistoryDataSource> dailyHistoryDataSourceProvider =
    Provider<DailyHistoryDataSource>((ref) {
      final JournalAccessState access = ref
          .watch(journalSessionControllerProvider)
          .requireValue;
      if (access case JournalUnlocked(:final session)) {
        return _SessionDailyHistoryDataSource(session);
      }
      throw StateError('Daily history requires an unlocked journal session.');
    });

final class _SessionDailyHistoryDataSource implements DailyHistoryDataSource {
  const _SessionDailyHistoryDataSource(this._session);

  final JournalSession _session;

  @override
  Future<DailyLogSnapshot?> find(String methodDate) {
    return _session.findDailyLog(methodDate);
  }
}

class DailyHistoryScreen extends ConsumerStatefulWidget {
  const DailyHistoryScreen({required this.methodDate, this.now, super.key});

  final String methodDate;
  final DateTime Function()? now;

  @override
  ConsumerState<DailyHistoryScreen> createState() => _DailyHistoryScreenState();
}

class _DailyHistoryScreenState extends ConsumerState<DailyHistoryScreen> {
  late final DateTime _today;
  late DateTime _viewedDate;
  late Future<DailyLogSnapshot?> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    validateJournalMethodDate(widget.methodDate);
    _today = _dateOnly(widget.now?.call() ?? DateTime.now());
    _viewedDate = _dateOnly(DateTime.parse(widget.methodDate));
    _snapshotFuture = _loadSnapshot();
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
                onPressed: _backToToday,
                tooltip: l10n.today,
                icon: const Icon(Icons.today_outlined),
              ),
              IconButton(
                onPressed: _previousDay,
                tooltip: l10n.previousDay,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: _chooseDate,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                  ),
                  child: Text(
                    material.formatFullDate(_viewedDate),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ),
              IconButton(
                onPressed: _canGoNext ? _nextDay : null,
                tooltip: l10n.nextDay,
                icon: const Icon(Icons.chevron_right),
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
            l10n.dailyHistoryReadOnly,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<DailyLogSnapshot?>(
              future: _snapshotFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(l10n.dailyHistoryLoadFailed));
                }
                final DailyLogSnapshot? daily = snapshot.data;
                if (daily == null || daily.entries.isEmpty) {
                  return DaymarkEmptyState(message: l10n.emptyHistoricalDaily);
                }
                return _buildEntries(context, daily.entries);
              },
            ),
          ),
          const DaymarkNoticeRegion(),
        ],
      ),
    );
  }

  Widget _buildEntries(BuildContext context, List<DailyLogEntry> entries) {
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final DailyLogEntry entry = entries[index];
        final TextStyle? entryStyle = Theme.of(context).textTheme.bodyLarge;
        final bool discarded = entry.taskState == JournalTaskState.discarded;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EntrySignifierMarks(entryId: entry.id),
              SizedBox(
                width: 28,
                child: Text(
                  _entrySymbol(entry),
                  textAlign: TextAlign.center,
                  style: discarded
                      ? Theme.of(context).textTheme.titleMedium
                            ?.copyWith(decoration: TextDecoration.lineThrough)
                      : Theme.of(context).textTheme.titleMedium,
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
                          ? entryStyle?.copyWith(
                              decoration: TextDecoration.lineThrough,
                            )
                          : entryStyle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool get _canGoNext => _viewedDate.isBefore(_today);

  Future<DailyLogSnapshot?> _loadSnapshot() {
    return _dataSource().find(formatJournalMethodDate(_viewedDate));
  }

  void _previousDay() {
    setState(() {
      _viewedDate = _dateOnly(_viewedDate.subtract(const Duration(days: 1)));
      _snapshotFuture = _loadSnapshot();
    });
  }

  void _nextDay() {
    if (!_canGoNext) {
      return;
    }
    final DateTime target = _dateOnly(_viewedDate.add(const Duration(days: 1)));
    if (target == _today) {
      _backToToday();
      return;
    }
    setState(() {
      _viewedDate = target;
      _snapshotFuture = _loadSnapshot();
    });
  }

  Future<void> _chooseDate() async {
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: _viewedDate,
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
      _backToToday();
      return;
    }
    if (target == _viewedDate) {
      return;
    }
    setState(() {
      _viewedDate = target;
      _snapshotFuture = _loadSnapshot();
    });
  }

  void _backToToday() {
    context.go('/');
  }

  DailyHistoryDataSource _dataSource() {
    return ref.read(dailyHistoryDataSourceProvider);
  }

  Future<void> _lock() {
    return ref.read(journalSessionControllerProvider.notifier).lock();
  }
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
