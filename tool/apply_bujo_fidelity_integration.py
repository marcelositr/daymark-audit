from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"expected integration block not found in {path}")
    file.write_text(text.replace(old, new, 1))


replace_once(
    "lib/features/journal/presentation/entry_signifiers.dart",
    """final FutureProviderFamily<Set<JournalSignifier>, String> entrySignifiersProvider =
    FutureProvider.family<Set<JournalSignifier>, String>((ref, entryId) {
""",
    """final entrySignifiersProvider =
    FutureProvider.family<Set<JournalSignifier>, String>((ref, entryId) {
""",
)

replace_once(
    "test/session/daily_task_migration_session_test.dart",
    """    expect(await session.findMonthlyLog('2026-09-01'), isNull);
    expect(
""",
    """    final monthlyDestinationCount = await session.database
        .customSelect(
          '''
          SELECT COUNT(*) AS count
          FROM logs
          WHERE kind = 'monthly' AND period_start = '2026-09-01'
          ''',
        )
        .getSingle();
    expect(monthlyDestinationCount.read<int>('count'), 0);
    expect(
""",
)

print("fidelity integration fixes staged")
