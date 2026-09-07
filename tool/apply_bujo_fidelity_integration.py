from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"expected integration block not found in {path}")
    file.write_text(text.replace(old, new, 1))


def replace_all(path: str, old: str, new: str, expected: int) -> None:
    file = Path(path)
    text = file.read_text()
    if text.count(new) >= expected:
        return
    count = text.count(old)
    if count != expected:
        raise SystemExit(
            f"expected {expected} integration blocks in {path}, found {count}"
        )
    file.write_text(text.replace(old, new))


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

replace_all(
    "test/journal/task_collection_migration_screen_test.dart",
    """    await tester.tap(find.text('Migrate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project'));
""",
    """    await tester.tap(find.text('Migrate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Collections'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project'));
""",
    2,
)

replace_all(
    "test/journal/entry_collection_reference_screen_test.dart",
    "find.text('○ Monthly event')",
    "find.text('Monthly event')",
    2,
)

replace_all(
    "test/journal/monthly_screen_test.dart",
    "find.text('○ Dentist')",
    "find.text('Dentist')",
    2,
)
replace_once(
    "test/journal/monthly_screen_test.dart",
    "expect(find.text('○ Historic meeting'), findsOneWidget);",
    "expect(find.text('Historic meeting'), findsOneWidget);",
)

print("fidelity integration fixes staged")
