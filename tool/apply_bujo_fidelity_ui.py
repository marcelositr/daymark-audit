from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"expected block not found in {path}")
    file.write_text(text.replace(old, new, 1))


def insert_before(path: str, anchor: str, insertion: str) -> None:
    file = Path(path)
    text = file.read_text()
    if insertion.strip() in text:
        return
    if anchor not in text:
        raise SystemExit(f"anchor not found in {path}")
    file.write_text(text.replace(anchor, insertion + anchor, 1))


# Monthly Calendar: dated Tasks + Signifiers.
replace_once(
    "lib/features/journal/presentation/monthly_screen.dart",
    "import 'entry_semantics.dart';\n",
    "import 'entry_semantics.dart';\nimport 'entry_signifiers.dart';\n",
)
replace_once(
    "lib/features/journal/presentation/monthly_screen.dart",
    "import 'journal_activity_guard.dart';\n",
    "import 'journal_activity_guard.dart';\nimport 'monthly_calendar_task_data_source.dart';\n",
)
replace_once(
    "lib/features/journal/presentation/monthly_screen.dart",
    "  bool _saving = false;\n",
    "  JournalEntryType _calendarEntryType = JournalEntryType.event;\n  bool _saving = false;\n",
)
replace_once(
    "lib/features/journal/presentation/monthly_screen.dart",
    """                        child: _followingCurrentMonth\n                            ? PopupMenuButton<_MonthlyEntryAction>(\n                                enabled: _entryActionId == null,\n                                tooltip: l10n.entryActions,\n                                padding: EdgeInsets.zero,\n                                onSelected: (action) {\n                                  unawaited(_applyEntryAction(entry, action));\n                                },\n                                itemBuilder: (context) => [\n                                  PopupMenuItem<_MonthlyEntryAction>(\n                                    value: _MonthlyEntryAction.reference,\n                                    child: Text(l10n.referenceEntry),\n                                  ),\n                                ],\n                                child: SizedBox(\n                                  width: double.infinity,\n                                  child: Text(\n                                    '○ ${entry.content}',\n                                    style: Theme.of(context)\n                                        .textTheme\n                                        .bodyLarge,\n                                  ),\n                                ),\n                              )\n                            : Text(\n                                '○ ${entry.content}',\n                                style: Theme.of(context).textTheme.bodyLarge,\n                              ),\n""",
    """                        child: _buildCalendarEntryRow(\n                          context,\n                          l10n,\n                          entry,\n                        ),\n""",
)
replace_once(
    "lib/features/journal/presentation/monthly_screen.dart",
    "  Widget _buildTasks(\n",
    """  Widget _buildCalendarEntryRow(\n    BuildContext context,\n    AppLocalizations l10n,\n    MonthlyLogEntry entry,\n  ) {\n    final bool actionInProgress = _entryActionId == entry.id;\n    final bool openTask =\n        entry.type == JournalEntryType.task &&\n        entry.taskState == JournalTaskState.open;\n    final TextStyle? entryStyle = Theme.of(context).textTheme.bodyLarge;\n    final Widget marker = actionInProgress\n        ? const Center(\n            child: SizedBox.square(\n              dimension: 16,\n              child: CircularProgressIndicator(strokeWidth: 2),\n            ),\n          )\n        : Text(\n            _monthlyCalendarEntrySymbol(entry),\n            textAlign: TextAlign.center,\n            style: entry.taskState == JournalTaskState.discarded\n                ? Theme.of(context).textTheme.titleMedium?.copyWith(\n                    decoration: TextDecoration.lineThrough,\n                  )\n                : Theme.of(context).textTheme.titleMedium,\n          );\n    final Widget row = Row(\n      crossAxisAlignment: CrossAxisAlignment.start,\n      children: [\n        EntrySignifierMarks(entryId: entry.id),\n        SizedBox(width: 28, child: marker),\n        const SizedBox(width: 8),\n        Expanded(\n          child: Semantics(\n            label: journalEntrySemanticLabel(\n              l10n,\n              type: entry.type,\n              taskState: entry.taskState,\n              content: entry.content,\n            ),\n            child: ExcludeSemantics(\n              child: Text(\n                entry.content,\n                style: entry.taskState == JournalTaskState.discarded\n                    ? entryStyle?.copyWith(\n                        decoration: TextDecoration.lineThrough,\n                      )\n                    : entryStyle,\n              ),\n            ),\n          ),\n        ),\n      ],\n    );\n    if (!_followingCurrentMonth || actionInProgress) {\n      return row;\n    }\n    return SizedBox(\n      width: double.infinity,\n      child: PopupMenuButton<_MonthlyEntryAction>(\n        enabled: _entryActionId == null,\n        tooltip: l10n.entryActions,\n        padding: EdgeInsets.zero,\n        onSelected: (action) {\n          unawaited(_applyEntryAction(entry, action));\n        },\n        itemBuilder: (context) => [\n          if (openTask)\n            PopupMenuItem(\n              value: _MonthlyEntryAction.complete,\n              child: Text(l10n.completeTask),\n            ),\n          if (openTask)\n            PopupMenuItem(\n              value: _MonthlyEntryAction.migrate,\n              child: Text(l10n.migrateTask),\n            ),\n          if (openTask)\n            PopupMenuItem(\n              value: _MonthlyEntryAction.schedule,\n              child: Text(l10n.scheduleTask),\n            ),\n          PopupMenuItem(\n            value: _MonthlyEntryAction.reference,\n            child: Text(l10n.referenceEntry),\n          ),\n          PopupMenuItem(\n            value: _MonthlyEntryAction.signifiers,\n            child: Text(l10n.signifiers),\n          ),\n          if (openTask)\n            PopupMenuItem(\n              value: _MonthlyEntryAction.discard,\n              child: Text(l10n.discardTask),\n            ),\n        ],\n        child: row,\n      ),\n    );\n  }\n\n  Widget _buildTasks(\n""",
)
# Only replace the first task-row children block after _buildTaskRow.
monthly = Path("lib/features/journal/presentation/monthly_screen.dart")
text = monthly.read_text()
needle = """  Widget _buildTaskRow(\n"""
pos = text.find(needle)
if pos < 0:
    raise SystemExit("monthly task row not found")
segment = text[pos:]
old = """      children: [\n        SizedBox(width: 28, child: marker),\n"""
new = """      children: [\n        EntrySignifierMarks(entryId: entry.id),\n        SizedBox(width: 28, child: marker),\n"""
if new not in segment:
    if old not in segment:
        raise SystemExit("monthly task row children not found")
    segment = segment.replace(old, new, 1)
    monthly.write_text(text[:pos] + segment)
replace_once(
    "lib/features/journal/presentation/monthly_screen.dart",
    """          if (!_reflecting)\n            PopupMenuItem(\n              value: _MonthlyEntryAction.reference,\n              child: Text(l10n.referenceEntry),\n            ),\n          if (openTask)\n""",
    """          if (!_reflecting)\n            PopupMenuItem(\n              value: _MonthlyEntryAction.reference,\n              child: Text(l10n.referenceEntry),\n            ),\n          if (!_reflecting)\n            PopupMenuItem(\n              value: _MonthlyEntryAction.signifiers,\n              child: Text(l10n.signifiers),\n            ),\n          if (openTask)\n""",
)
replace_once(
    "lib/features/journal/presentation/monthly_screen.dart",
    """          const SizedBox(width: 12),\n        ],\n        Expanded(\n""",
    """          const SizedBox(width: 12),\n          DaymarkDropdownButton<JournalEntryType>(\n            value: _calendarEntryType,\n            onChanged: _saving\n                ? null\n                : (value) {\n                    if (value != null) {\n                      setState(() => _calendarEntryType = value);\n                      _restoreComposerFocus();\n                    }\n                  },\n            items: [\n              DropdownMenuItem(\n                value: JournalEntryType.event,\n                child: Text(l10n.entryEvent),\n              ),\n              DropdownMenuItem(\n                value: JournalEntryType.task,\n                child: Text(l10n.entryTask),\n              ),\n            ],\n          ),\n          const SizedBox(width: 12),\n        ],\n        Expanded(\n""",
)
replace_once(
    "lib/features/journal/presentation/monthly_screen.dart",
    """                hintText: calendar\n                    ? l10n.monthlyEventHint\n                    : l10n.monthlyTaskHint,\n""",
    """                hintText: calendar\n                    ? (_calendarEntryType == JournalEntryType.task\n                          ? l10n.monthlyCalendarTaskHint\n                          : l10n.monthlyEventHint)\n                    : l10n.monthlyTaskHint,\n""",
)
replace_once(
    "lib/features/journal/presentation/monthly_screen.dart",
    """      if (section == JournalMonthlySection.calendar) {\n        await dataSource.captureCalendarEvent(\n          logId: snapshot.logId,\n          calendarDate: _formatMethodDate(\n            DateTime(month.year, month.month, selectedDay),\n          ),\n          content: content,\n        );\n      } else {\n""",
    """      if (section == JournalMonthlySection.calendar) {\n        final String calendarDate = _formatMethodDate(\n          DateTime(month.year, month.month, selectedDay),\n        );\n        if (_calendarEntryType == JournalEntryType.task) {\n          await ref\n              .read(monthlyCalendarTaskDataSourceProvider)\n              .capture(\n                logId: snapshot.logId,\n                calendarDate: calendarDate,\n                content: content,\n              );\n        } else {\n          await dataSource.captureCalendarEvent(\n            logId: snapshot.logId,\n            calendarDate: calendarDate,\n            content: content,\n          );\n        }\n      } else {\n""",
)
replace_once(
    "lib/features/journal/presentation/monthly_screen.dart",
    """    if (_reflecting && action == _MonthlyEntryAction.reference) {\n      return;\n    }\n    final bool openTask =\n        entry.type == JournalEntryType.task &&\n        entry.taskState == JournalTaskState.open;\n    if (action != _MonthlyEntryAction.reference && !openTask) {\n      return;\n    }\n\n    final DateTime actionMonth = _month;\n""",
    """    if (_reflecting &&\n        (action == _MonthlyEntryAction.reference ||\n            action == _MonthlyEntryAction.signifiers)) {\n      return;\n    }\n    final bool openTask =\n        entry.type == JournalEntryType.task &&\n        entry.taskState == JournalTaskState.open;\n    if (action != _MonthlyEntryAction.reference &&\n        action != _MonthlyEntryAction.signifiers &&\n        !openTask) {\n      return;\n    }\n    if (action == _MonthlyEntryAction.signifiers) {\n      try {\n        await showEntrySignifierDialog(\n          context: context,\n          ref: ref,\n          entryId: entry.id,\n        );\n      } catch (error, stackTrace) {\n        _reportUnexpectedMonthlyError('signifiers', error, stackTrace);\n        if (mounted) {\n          ref\n              .read(daymarkNoticeProvider.notifier)\n              .showError(AppLocalizations.of(context).signifierUpdateFailed);\n        }\n      }\n      return;\n    }\n\n    final DateTime actionMonth = _month;\n""",
)
replace_once(
    "lib/features/journal/presentation/monthly_screen.dart",
    """        case _MonthlyEntryAction.discard:\n          await dataSource.discardTask(entryId: entry.id);\n          break;\n""",
    """        case _MonthlyEntryAction.discard:\n          await dataSource.discardTask(entryId: entry.id);\n          break;\n        case _MonthlyEntryAction.signifiers:\n          break;\n""",
)
replace_once(
    "lib/features/journal/presentation/monthly_screen.dart",
    "enum _MonthlyEntryAction { complete, migrate, schedule, reference, discard }\n",
    """enum _MonthlyEntryAction {\n  complete,\n  migrate,\n  schedule,\n  reference,\n  signifiers,\n  discard,\n}\n""",
)
insert_before(
    "lib/features/journal/presentation/monthly_screen.dart",
    "String _taskSymbol(JournalTaskState? state) => switch (state) {\n",
    """String _monthlyCalendarEntrySymbol(MonthlyLogEntry entry) =>\n    switch (entry.type) {\n      JournalEntryType.task => _taskSymbol(entry.taskState),\n      JournalEntryType.event => '○',\n      JournalEntryType.note => '–',\n    };\n\n""",
)

# Today: Signifiers.
replace_once(
    "lib/features/journal/presentation/today_screen.dart",
    "import 'entry_semantics.dart';\n",
    "import 'entry_semantics.dart';\nimport 'entry_signifiers.dart';\n",
)
today = Path("lib/features/journal/presentation/today_screen.dart")
text = today.read_text()
old = """      children: [\n        SizedBox(width: 28, child: marker),\n"""
new = """      children: [\n        EntrySignifierMarks(entryId: entry.id),\n        SizedBox(width: 28, child: marker),\n"""
if new not in text:
    if old not in text:
        raise SystemExit("today row children not found")
    today.write_text(text.replace(old, new, 1))
replace_once(
    "lib/features/journal/presentation/today_screen.dart",
    """          if (!_reflecting)\n            PopupMenuItem(\n              value: _EntryAction.reference,\n              child: Text(l10n.referenceEntry),\n            ),\n          if (openTask)\n""",
    """          if (!_reflecting)\n            PopupMenuItem(\n              value: _EntryAction.reference,\n              child: Text(l10n.referenceEntry),\n            ),\n          if (!_reflecting)\n            PopupMenuItem(\n              value: _EntryAction.signifiers,\n              child: Text(l10n.signifiers),\n            ),\n          if (openTask)\n""",
)
replace_once(
    "lib/features/journal/presentation/today_screen.dart",
    """    if (action != _EntryAction.reference && !openTask) {\n      return;\n    }\n\n    final DateTime actionDate = _today;\n""",
    """    if (action != _EntryAction.reference &&\n        action != _EntryAction.signifiers &&\n        !openTask) {\n      return;\n    }\n    if (action == _EntryAction.signifiers) {\n      try {\n        await showEntrySignifierDialog(\n          context: context,\n          ref: ref,\n          entryId: entry.id,\n        );\n      } catch (error, stackTrace) {\n        _reportUnexpectedJournalError('signifiers', error, stackTrace);\n        if (mounted) {\n          ref\n              .read(daymarkNoticeProvider.notifier)\n              .showError(AppLocalizations.of(context).signifierUpdateFailed);\n        }\n      }\n      return;\n    }\n\n    final DateTime actionDate = _today;\n""",
)
replace_once(
    "lib/features/journal/presentation/today_screen.dart",
    """        case _EntryAction.discard:\n          await dataSource.discardTask(entryId: entry.id);\n          break;\n""",
    """        case _EntryAction.discard:\n          await dataSource.discardTask(entryId: entry.id);\n          break;\n        case _EntryAction.signifiers:\n          break;\n""",
)
replace_once(
    "lib/features/journal/presentation/today_screen.dart",
    "enum _EntryAction { complete, migrate, schedule, reference, discard }\n",
    "enum _EntryAction { complete, migrate, schedule, reference, signifiers, discard }\n",
)

# Future overview: Signifiers and arrived Event detection.
replace_once(
    "lib/features/journal/presentation/future_screen.dart",
    "import 'entry_semantics.dart';\n",
    "import 'entry_semantics.dart';\nimport 'entry_signifiers.dart';\n",
)
replace_once(
    "lib/features/journal/presentation/future_screen.dart",
    """              final bool hasOpenTasks =\n                  arrived?.entries.any(\n                    (entry) =>\n                        entry.type == JournalEntryType.task &&\n                        entry.taskState == JournalTaskState.open,\n                  ) ??\n                  false;\n              if (!hasOpenTasks) {\n""",
    """              final bool hasReviewableEntries =\n                  arrived?.entries.any(\n                    (entry) =>\n                        (entry.type == JournalEntryType.task &&\n                            entry.taskState == JournalTaskState.open) ||\n                        (entry.type == JournalEntryType.event &&\n                            !entry.hasOutgoingMigration),\n                  ) ??\n                  false;\n              if (!hasReviewableEntries) {\n""",
)
future = Path("lib/features/journal/presentation/future_screen.dart")
text = future.read_text()
if new not in text:
    if old not in text:
        raise SystemExit("future row children not found")
    future.write_text(text.replace(old, new, 1))
replace_once(
    "lib/features/journal/presentation/future_screen.dart",
    """          PopupMenuItem(\n            value: _FutureEntryAction.reference,\n            child: Text(l10n.referenceEntry),\n          ),\n          if (openTask)\n""",
    """          PopupMenuItem(\n            value: _FutureEntryAction.reference,\n            child: Text(l10n.referenceEntry),\n          ),\n          PopupMenuItem(\n            value: _FutureEntryAction.signifiers,\n            child: Text(l10n.signifiers),\n          ),\n          if (openTask)\n""",
)
replace_once(
    "lib/features/journal/presentation/future_screen.dart",
    """    if (action != _FutureEntryAction.reference && !openTask) {\n      return;\n    }\n\n    String? referenceCollectionId;\n""",
    """    if (action != _FutureEntryAction.reference &&\n        action != _FutureEntryAction.signifiers &&\n        !openTask) {\n      return;\n    }\n    if (action == _FutureEntryAction.signifiers) {\n      try {\n        await showEntrySignifierDialog(\n          context: context,\n          ref: ref,\n          entryId: entry.id,\n        );\n      } catch (error, stackTrace) {\n        _reportUnexpectedFutureError('signifiers', error, stackTrace);\n        if (mounted) {\n          ref\n              .read(daymarkNoticeProvider.notifier)\n              .showError(AppLocalizations.of(context).signifierUpdateFailed);\n        }\n      }\n      return;\n    }\n\n    String? referenceCollectionId;\n""",
)
replace_once(
    "lib/features/journal/presentation/future_screen.dart",
    """        case _FutureEntryAction.discard:\n          await dataSource.discardTask(entryId: entry.id);\n          break;\n""",
    """        case _FutureEntryAction.discard:\n          await dataSource.discardTask(entryId: entry.id);\n          break;\n        case _FutureEntryAction.signifiers:\n          break;\n""",
)
replace_once(
    "lib/features/journal/presentation/future_screen.dart",
    "enum _FutureEntryAction { complete, reference, discard }\n",
    "enum _FutureEntryAction { complete, reference, signifiers, discard }\n",
)

# Arrived Future review: Tasks + Events, with chosen Calendar day.
replace_once(
    "lib/features/journal/presentation/future_history_screen.dart",
    "import 'entry_semantics.dart';\n",
    "import 'entry_semantics.dart';\nimport 'entry_signifiers.dart';\nimport 'future_event_migration_data_source.dart';\n",
)
replace_once(
    "lib/features/journal/presentation/future_history_screen.dart",
    """        final bool openTask =\n            entry.type == JournalEntryType.task &&\n            entry.taskState == JournalTaskState.open;\n""",
    """        final bool openTask =\n            entry.type == JournalEntryType.task &&\n            entry.taskState == JournalTaskState.open;\n        final bool reviewableEvent =\n            entry.type == JournalEntryType.event &&\n            !entry.hasOutgoingMigration;\n""",
)
history = Path("lib/features/journal/presentation/future_history_screen.dart")
text = history.read_text()
old_history_row = """          children: [\n            SizedBox(width: 28, child: marker),\n"""
new_history_row = """          children: [\n            EntrySignifierMarks(entryId: entry.id),\n            SizedBox(width: 28, child: marker),\n"""
if new_history_row not in text:
    if old_history_row not in text:
        raise SystemExit("future history row children not found")
    history.write_text(text.replace(old_history_row, new_history_row, 1))
replace_once(
    "lib/features/journal/presentation/future_history_screen.dart",
    """          child: !_arrivedCurrentMonth || !openTask || actionInProgress\n              ? row\n              : SizedBox(\n""",
    """          child: !_arrivedCurrentMonth ||\n                  (!openTask && !reviewableEvent) ||\n                  actionInProgress\n              ? row\n              : SizedBox(\n""",
)
replace_once(
    "lib/features/journal/presentation/future_history_screen.dart",
    """                          PopupMenuItem<_FutureArrivalAction>(\n                            value: _FutureArrivalAction.migrateToMonthly,\n                            child: Text(l10n.migrateToCurrentMonth),\n                          ),\n                          PopupMenuItem<_FutureArrivalAction>(\n                            value: _FutureArrivalAction.complete,\n                            child: Text(l10n.completeTask),\n                          ),\n                          PopupMenuItem<_FutureArrivalAction>(\n                            value: _FutureArrivalAction.discard,\n                            child: Text(l10n.discardTask),\n                          ),\n""",
    """                          if (openTask)\n                            PopupMenuItem<_FutureArrivalAction>(\n                              value: _FutureArrivalAction.migrateToMonthly,\n                              child: Text(l10n.migrateToCurrentMonth),\n                            ),\n                          if (reviewableEvent)\n                            PopupMenuItem<_FutureArrivalAction>(\n                              value: _FutureArrivalAction.migrateEventToCalendar,\n                              child: Text(l10n.migrateEventToCalendar),\n                            ),\n                          if (openTask)\n                            PopupMenuItem<_FutureArrivalAction>(\n                              value: _FutureArrivalAction.complete,\n                              child: Text(l10n.completeTask),\n                            ),\n                          if (openTask)\n                            PopupMenuItem<_FutureArrivalAction>(\n                              value: _FutureArrivalAction.discard,\n                              child: Text(l10n.discardTask),\n                            ),\n""",
)
replace_once(
    "lib/features/journal/presentation/future_history_screen.dart",
    """    final bool openTask =\n        entry.type == JournalEntryType.task &&\n        entry.taskState == JournalTaskState.open;\n    if (!openTask) {\n      return;\n    }\n\n    setState(() => _entryActionId = entry.id);\n""",
    """    final bool openTask =\n        entry.type == JournalEntryType.task &&\n        entry.taskState == JournalTaskState.open;\n    final bool reviewableEvent =\n        entry.type == JournalEntryType.event && !entry.hasOutgoingMigration;\n    if (!openTask && !reviewableEvent) {\n      return;\n    }\n\n    String? eventCalendarDate;\n    if (action == _FutureArrivalAction.migrateEventToCalendar) {\n      if (!reviewableEvent) {\n        return;\n      }\n      final DateTime firstDate = DateTime(_month.year, _month.month);\n      final DateTime lastDate = DateTime(_month.year, _month.month + 1, 0);\n      final DateTime now = _now();\n      final DateTime initialDate =\n          now.isBefore(firstDate) || now.isAfter(lastDate) ? firstDate : now;\n      final DateTime? selectedDate = await showDatePicker(\n        context: context,\n        initialDate: initialDate,\n        firstDate: firstDate,\n        lastDate: lastDate,\n      );\n      if (!mounted || selectedDate == null) {\n        return;\n      }\n      eventCalendarDate =\n          '${selectedDate.year.toString().padLeft(4, '0')}-'\n          '${selectedDate.month.toString().padLeft(2, '0')}-'\n          '${selectedDate.day.toString().padLeft(2, '0')}';\n    }\n\n    setState(() => _entryActionId = entry.id);\n""",
)
replace_once(
    "lib/features/journal/presentation/future_history_screen.dart",
    """        case _FutureArrivalAction.complete:\n          await dataSource.completeTask(entryId: entry.id);\n          break;\n""",
    """        case _FutureArrivalAction.migrateEventToCalendar:\n          await ref\n              .read(futureEventMigrationDataSourceProvider)\n              .migrateToMonthlyCalendar(\n                entryId: entry.id,\n                periodStart: widget.periodStart,\n                calendarDate: eventCalendarDate!,\n              );\n          break;\n        case _FutureArrivalAction.complete:\n          await dataSource.completeTask(entryId: entry.id);\n          break;\n""",
)
replace_once(
    "lib/features/journal/presentation/future_history_screen.dart",
    "enum _FutureArrivalAction { migrateToMonthly, complete, discard }\n",
    """enum _FutureArrivalAction {\n  migrateToMonthly,\n  migrateEventToCalendar,\n  complete,\n  discard,\n}\n""",
)
replace_once(
    "lib/features/journal/presentation/future_history_screen.dart",
    "  JournalEntryType.event => '○',\n",
    "  JournalEntryType.event => entry.hasOutgoingMigration ? '>' : '○',\n",
)

# Collections: Signifiers for all owned entry types.
replace_once(
    "lib/features/journal/presentation/collections_screen.dart",
    "import 'entry_semantics.dart';\n",
    "import 'entry_semantics.dart';\nimport 'entry_signifiers.dart';\n",
)
collections = Path("lib/features/journal/presentation/collections_screen.dart")
text = collections.read_text()
pos = text.find("  Widget _buildEntry(AppLocalizations l10n, CollectionEntry entry) {")
if pos < 0:
    raise SystemExit("collection entry builder not found")
segment = text[pos:]
old_collection_row = """      children: [\n        SizedBox(width: 28, child: marker),\n"""
new_collection_row = """      children: [\n        EntrySignifierMarks(entryId: entry.id),\n        SizedBox(width: 28, child: marker),\n"""
if new_collection_row not in segment:
    if old_collection_row not in segment:
        raise SystemExit("collection row children not found")
    segment = segment.replace(old_collection_row, new_collection_row, 1)
    collections.write_text(text[:pos] + segment)
replace_once(
    "lib/features/journal/presentation/collections_screen.dart",
    """    if (!openTask || actionInProgress) return row;\n\n    return SizedBox(\n""",
    """    if (actionInProgress) return row;\n\n    return SizedBox(\n""",
)
replace_once(
    "lib/features/journal/presentation/collections_screen.dart",
    """        itemBuilder: (context) => [\n          PopupMenuItem(\n            value: _CollectionTaskAction.complete,\n            child: Text(l10n.completeTask),\n          ),\n          PopupMenuItem(\n            value: _CollectionTaskAction.discard,\n            child: Text(l10n.discardTask),\n          ),\n        ],\n""",
    """        itemBuilder: (context) => [\n          if (openTask)\n            PopupMenuItem(\n              value: _CollectionTaskAction.complete,\n              child: Text(l10n.completeTask),\n            ),\n          PopupMenuItem(\n            value: _CollectionTaskAction.signifiers,\n            child: Text(l10n.signifiers),\n          ),\n          if (openTask)\n            PopupMenuItem(\n              value: _CollectionTaskAction.discard,\n              child: Text(l10n.discardTask),\n            ),\n        ],\n""",
)
replace_once(
    "lib/features/journal/presentation/collections_screen.dart",
    """    final String? collectionId = _selectedCollectionId;\n    if (collectionId == null || _taskActionEntryId != null) return;\n    // Any deliberate journal action supersedes the short-lived capture Undo.\n""",
    """    final String? collectionId = _selectedCollectionId;\n    if (collectionId == null || _taskActionEntryId != null) return;\n    if (action == _CollectionTaskAction.signifiers) {\n      try {\n        await showEntrySignifierDialog(\n          context: context,\n          ref: ref,\n          entryId: entry.id,\n        );\n      } catch (error, stackTrace) {\n        _reportUnexpectedCollectionsError('signifiers', error, stackTrace);\n        if (mounted) {\n          ref\n              .read(daymarkNoticeProvider.notifier)\n              .showError(AppLocalizations.of(context).signifierUpdateFailed);\n        }\n      }\n      return;\n    }\n    final bool openTask =\n        entry.type == JournalEntryType.task &&\n        entry.taskState == JournalTaskState.open;\n    if (!openTask) {\n      return;\n    }\n    // Any deliberate journal action supersedes the short-lived capture Undo.\n""",
)
replace_once(
    "lib/features/journal/presentation/collections_screen.dart",
    """        case _CollectionTaskAction.discard:\n          await _dataSource().discardTask(entryId: entry.id);\n      }\n""",
    """        case _CollectionTaskAction.discard:\n          await _dataSource().discardTask(entryId: entry.id);\n        case _CollectionTaskAction.signifiers:\n          break;\n      }\n""",
)
replace_once(
    "lib/features/journal/presentation/collections_screen.dart",
    "enum _CollectionTaskAction { complete, discard }\n",
    "enum _CollectionTaskAction { complete, signifiers, discard }\n",
)

print("UI fidelity changes staged")
