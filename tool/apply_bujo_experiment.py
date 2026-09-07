from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old in text:
        file.write_text(text.replace(old, new, 1))
        return
    if new in text:
        return
    raise SystemExit(f"expected source block not found in {path}")


Path("lib/features/journal/presentation/rapid_log_input.dart").write_text(
    """import 'package:daymark/features/journal/domain/journal_domain.dart';

final class RapidLogInput {
  const RapidLogInput({required this.type, required this.content});

  final JournalEntryType type;
  final String content;
}

RapidLogInput parseRapidLogInput(
  String raw, {
  required JournalEntryType fallbackType,
}) {
  final String input = raw.trim();
  if (input.isEmpty) {
    return RapidLogInput(type: fallbackType, content: '');
  }

  final ({String marker, JournalEntryType type})? signifier = switch (input) {
    String value when value == '•' || value.startsWith('• ') => (
      marker: '•',
      type: JournalEntryType.task,
    ),
    String value when value == '○' || value.startsWith('○ ') => (
      marker: '○',
      type: JournalEntryType.event,
    ),
    String value when value == '–' || value.startsWith('– ') => (
      marker: '–',
      type: JournalEntryType.note,
    ),
    String value when value == '-' || value.startsWith('- ') => (
      marker: '-',
      type: JournalEntryType.note,
    ),
    _ => null,
  };

  if (signifier == null) {
    return RapidLogInput(type: fallbackType, content: input);
  }

  return RapidLogInput(
    type: signifier.type,
    content: input.substring(signifier.marker.length).trimLeft(),
  );
}
"""
)

Path("test/journal/rapid_log_input_test.dart").write_text(
    """import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:daymark/features/journal/presentation/rapid_log_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical Rapid Logging signifiers override the selected type', () {
    expect(
      parseRapidLogInput('• Carry task', fallbackType: JournalEntryType.note),
      isA<RapidLogInput>()
          .having((value) => value.type, 'type', JournalEntryType.task)
          .having((value) => value.content, 'content', 'Carry task'),
    );
    expect(
      parseRapidLogInput('○ Dentist', fallbackType: JournalEntryType.task),
      isA<RapidLogInput>()
          .having((value) => value.type, 'type', JournalEntryType.event)
          .having((value) => value.content, 'content', 'Dentist'),
    );
    expect(
      parseRapidLogInput('– Observation', fallbackType: JournalEntryType.task),
      isA<RapidLogInput>()
          .having((value) => value.type, 'type', JournalEntryType.note)
          .having((value) => value.content, 'content', 'Observation'),
    );
    expect(
      parseRapidLogInput('- ASCII note', fallbackType: JournalEntryType.event),
      isA<RapidLogInput>()
          .having((value) => value.type, 'type', JournalEntryType.note)
          .having((value) => value.content, 'content', 'ASCII note'),
    );
  });

  test('plain or ambiguous text keeps the selected type', () {
    expect(
      parseRapidLogInput('Plain capture', fallbackType: JournalEntryType.event),
      isA<RapidLogInput>()
          .having((value) => value.type, 'type', JournalEntryType.event)
          .having((value) => value.content, 'content', 'Plain capture'),
    );
    expect(
      parseRapidLogInput('-5 degrees', fallbackType: JournalEntryType.task),
      isA<RapidLogInput>()
          .having((value) => value.type, 'type', JournalEntryType.task)
          .having((value) => value.content, 'content', '-5 degrees'),
    );
  });

  test('a signifier without content stays empty', () {
    final RapidLogInput input = parseRapidLogInput(
      '•',
      fallbackType: JournalEntryType.event,
    );
    expect(input.type, JournalEntryType.task);
    expect(input.content, isEmpty);
  });
}
"""
)

for path in (
    "lib/features/journal/presentation/today_screen.dart",
    "lib/features/journal/presentation/future_screen.dart",
    "lib/features/journal/presentation/collections_screen.dart",
):
    replace_once(
        path,
        "import 'journal_activity_guard.dart';\n",
        "import 'journal_activity_guard.dart';\nimport 'rapid_log_input.dart';\n",
    )

replace_once(
    "lib/features/journal/presentation/today_screen.dart",
    """  Future<void> _capture() async {
    final String content = _entryController.text.trim();
    if (content.isEmpty || _saving) {
      return;
    }
""",
    """  Future<void> _capture() async {
    final RapidLogInput rapidLog = parseRapidLogInput(
      _entryController.text,
      fallbackType: _entryType,
    );
    if (rapidLog.content.isEmpty || _saving) {
      return;
    }
""",
)
replace_once(
    "lib/features/journal/presentation/today_screen.dart",
    """      await dataSource.capture(
        logId: snapshot.logId,
        type: _entryType,
        content: content,
      );
""",
    """      await dataSource.capture(
        logId: snapshot.logId,
        type: rapidLog.type,
        content: rapidLog.content,
      );
""",
)

replace_once(
    "lib/features/journal/presentation/future_screen.dart",
    """  Future<void> _capture() async {
    final String content = _entryController.text.trim();
    if (content.isEmpty || _saving) {
      return;
    }

    final DateTime selectedMonth = _selectedMonth;
    final JournalEntryType entryType = _entryType;
""",
    """  Future<void> _capture() async {
    final RapidLogInput rapidLog = parseRapidLogInput(
      _entryController.text,
      fallbackType: _entryType,
    );
    if (rapidLog.content.isEmpty || _saving) {
      return;
    }

    final DateTime selectedMonth = _selectedMonth;
""",
)
replace_once(
    "lib/features/journal/presentation/future_screen.dart",
    """      await dataSource.capture(
        logId: target.logId,
        type: entryType,
        content: content,
      );
""",
    """      await dataSource.capture(
        logId: target.logId,
        type: rapidLog.type,
        content: rapidLog.content,
      );
""",
)

replace_once(
    "lib/features/journal/presentation/collections_screen.dart",
    """  Future<void> _capture() async {
    final String content = _entryController.text.trim();
    final String? collectionId = _selectedCollectionId;
    if (content.isEmpty || collectionId == null || _saving) return;
""",
    """  Future<void> _capture() async {
    final RapidLogInput rapidLog = parseRapidLogInput(
      _entryController.text,
      fallbackType: _entryType,
    );
    final String? collectionId = _selectedCollectionId;
    if (rapidLog.content.isEmpty || collectionId == null || _saving) return;
""",
)
replace_once(
    "lib/features/journal/presentation/collections_screen.dart",
    """      await _dataSource().capture(
        collectionId: collectionId,
        type: _entryType,
        content: content,
      );
""",
    """      await _dataSource().capture(
        collectionId: collectionId,
        type: rapidLog.type,
        content: rapidLog.content,
      );
""",
)

monthly = "lib/features/journal/presentation/monthly_screen.dart"
replace_once(
    monthly,
    """  bool _saving = false;
  bool _trackerSaving = false;
  String? _entryActionId;
""",
    """  bool _saving = false;
  bool _trackerSaving = false;
  bool _reflecting = false;
  String? _entryActionId;
""",
)
replace_once(
    monthly,
    """              IconButton(
                onPressed: _lock,
                tooltip: l10n.lockJournal,
                icon: const Icon(Icons.lock_outline),
              ),
""",
    """              if (_followingCurrentMonth &&
                  _section == _MonthlyViewSection.tasks)
                IconButton(
                  onPressed: busy ? null : _toggleReflection,
                  tooltip: _reflecting
                      ? l10n.finishReflection
                      : l10n.startReflection,
                  icon: Icon(
                    _reflecting
                        ? Icons.fact_check
                        : Icons.fact_check_outlined,
                  ),
                ),
              IconButton(
                onPressed: _lock,
                tooltip: l10n.lockJournal,
                icon: const Icon(Icons.lock_outline),
              ),
""",
)
replace_once(
    monthly,
    """          if (!_followingCurrentMonth) ...[
            const SizedBox(height: 4),
            Text(
              l10n.monthlyHistoryReadOnly,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
""",
    """          if (!_followingCurrentMonth) ...[
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
""",
)
replace_once(
    monthly,
    """                      _entryController.clear();
                      setState(() => _section = selection.single);
                      if (_section == _MonthlyViewSection.tracker) {
""",
    """                      _entryController.clear();
                      final _MonthlyViewSection nextSection = selection.single;
                      setState(() {
                        _section = nextSection;
                        if (nextSection != _MonthlyViewSection.tasks) {
                          _reflecting = false;
                        }
                      });
                      if (_section == _MonthlyViewSection.tracker) {
""",
)
replace_once(
    monthly,
    """          if (_followingCurrentMonth &&
              _section != _MonthlyViewSection.tracker) ...[
""",
    """          if (_followingCurrentMonth &&
              _section != _MonthlyViewSection.tracker &&
              !_reflecting) ...[
""",
)
replace_once(
    monthly,
    """    final List<MonthlyLogEntry> taskEntries =
        snapshot?.taskEntries ?? const <MonthlyLogEntry>[];
    if (taskEntries.isEmpty) {
      return DaymarkEmptyState(message: l10n.emptyMonthlyTasks, topPadding: 16);
    }
""",
    """    final List<MonthlyLogEntry> allTaskEntries =
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
""",
)
replace_once(
    monthly,
    """          PopupMenuItem(
            value: _MonthlyEntryAction.reference,
            child: Text(l10n.referenceEntry),
          ),
""",
    """          if (!_reflecting)
            PopupMenuItem(
              value: _MonthlyEntryAction.reference,
              child: Text(l10n.referenceEntry),
            ),
""",
)
replace_once(
    monthly,
    """    if (defaultTargetPlatform != TargetPlatform.linux ||
        !_followingCurrentMonth ||
        _section == _MonthlyViewSection.tracker ||
        _saving ||
""",
    """    if (defaultTargetPlatform != TargetPlatform.linux ||
        !_followingCurrentMonth ||
        _section == _MonthlyViewSection.tracker ||
        _reflecting ||
        _saving ||
""",
)
replace_once(
    monthly,
    """      if (mounted &&
          _followingCurrentMonth &&
          _section != _MonthlyViewSection.tracker &&
          !_saving &&
""",
    """      if (mounted &&
          _followingCurrentMonth &&
          _section != _MonthlyViewSection.tracker &&
          !_reflecting &&
          !_saving &&
""",
)
replace_once(
    monthly,
    """      _month = target;
      _followingCurrentMonth = followingCurrentMonth;
      _selectedDay = followingCurrentMonth ? _clampDay(now.day, target) : 1;
""",
    """      _month = target;
      _followingCurrentMonth = followingCurrentMonth;
      _reflecting = false;
      _selectedDay = followingCurrentMonth ? _clampDay(now.day, target) : 1;
""",
)
replace_once(
    monthly,
    """    if (content.isEmpty ||
        _saving ||
        !_followingCurrentMonth ||
        _section == _MonthlyViewSection.tracker) {
""",
    """    if (content.isEmpty ||
        _saving ||
        _reflecting ||
        !_followingCurrentMonth ||
        _section == _MonthlyViewSection.tracker) {
""",
)
replace_once(
    monthly,
    """    if (_entryActionId != null || !_followingCurrentMonth) {
      return;
    }
    final bool openTask =
""",
    """    if (_entryActionId != null || !_followingCurrentMonth) {
      return;
    }
    if (_reflecting && action == _MonthlyEntryAction.reference) {
      return;
    }
    final bool openTask =
""",
)
replace_once(
    monthly,
    """  Future<void> _lock() async {
""",
    """  void _toggleReflection() {
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
""",
)
replace_once(
    monthly,
    """    setState(() {
      _month = currentMonth;
      _selectedDay = _clampDay(now.day, _month);
""",
    """    setState(() {
      _month = currentMonth;
      _reflecting = false;
      _selectedDay = _clampDay(now.day, _month);
""",
)
