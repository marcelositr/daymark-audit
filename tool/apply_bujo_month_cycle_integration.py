from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"expected integration block not found in {path}")
    file.write_text(text.replace(old, new, 1))


session = Path("lib/core/session/journal_session.dart")
text = session.read_text()
if "import 'package:drift/drift.dart';" not in text:
    text = text.replace(
        "import 'package:uuid/uuid.dart';",
        "import 'package:drift/drift.dart';\nimport 'package:uuid/uuid.dart';",
        1,
    )
session.write_text(text)

history = Path("lib/features/journal/presentation/future_history_screen.dart")
text = history.read_text()
if not text.startswith("import 'dart:async';"):
    text = "import 'dart:async';\n\n" + text
text = text.replace("import 'package:flutter/foundation.dart';\n", "", 1)
text = text.replace(
    "                      _applyArrivalAction(entry, action);",
    "                      unawaited(_applyArrivalAction(entry, action));",
    1,
)
history.write_text(text)

replace_once(
    "lib/features/journal/presentation/today_screen.dart",
    """        case TaskMigrationDestination.collection:
          migrationCollectionId = await showTaskCollectionMigrationDialog(
""",
    """        case TaskMigrationDestination.nextMonth:
          return;
        case TaskMigrationDestination.collection:
          migrationCollectionId = await showTaskCollectionMigrationDialog(
""",
)

for path in (
    "test/journal/entry_collection_reference_screen_test.dart",
    "test/journal/future_screen_test.dart",
):
    replace_once(
        path,
        """  @override
  Future<void> capture({
""",
        """  @override
  Future<FutureLogSnapshot?> find(String periodStart) async => null;

  @override
  Future<void> capture({
""",
    )

replace_once(
    "test/journal/future_history_screen_test.dart",
    """  @override
  Future<FutureLogSnapshot?> find(String periodStart) async {
""",
    """  @override
  Future<void> completeTask({required String entryId}) async {}

  @override
  Future<void> discardTask({required String entryId}) async {}

  @override
  Future<FutureLogSnapshot?> find(String periodStart) async {
""",
)
