from pathlib import Path
import re


def replace_required(path_name: str, old: str, new: str) -> None:
    path = Path(path_name)
    text = path.read_text()
    if new in text:
        return
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"{path_name}: expected one repair marker, found {count}: {old[:80]!r}"
        )
    path.write_text(text.replace(old, new, 1))


# Riverpod 3 in this pinned Flutter toolchain does not expose
# AsyncValue.valueOrNull. Keep the fixed signifier lane while using
# a supported non-throwing read.
path = Path("lib/features/journal/presentation/entry_signifiers.dart")
text = path.read_text()
if ".valueOrNull" in text:
    text = text.replace(
        ".valueOrNull",
        ".whenOrNull(data: (value) => value)",
    )
path.write_text(text)

# Typo introduced in the transported visibility-toggle patch.
path = Path("lib/features/journal/presentation/open_export_dialog.dart")
text = path.read_text().replace("hidePasssword", "hidePassword")
path.write_text(text)

# Keep the selected signifier set mutable, but the field reference itself
# final. Normalize import groups for directives_ordering.
path = Path("lib/features/journal/presentation/search_screen.dart")
text = path.read_text()
text = text.replace(
    "  Set<JournalSignifier> _selectedSignifiers =",
    "  final Set<JournalSignifier> _selectedSignifiers =",
)
lines = text.splitlines()
end = 0
while end < len(lines) and (lines[end].startswith("import ") or not lines[end].strip()):
    end += 1
imports = [line for line in lines[:end] if line.startswith("import ")]
dart_imports = sorted(line for line in imports if "'dart:" in line)
package_imports = sorted(line for line in imports if "'package:" in line)
relative_imports = sorted(
    line
    for line in imports
    if "'dart:" not in line and "'package:" not in line
)
groups = [group for group in (dart_imports, package_imports, relative_imports) if group]
import_block: list[str] = []
for index, group in enumerate(groups):
    if index:
        import_block.append("")
    import_block.extend(group)
path.write_text("\n".join(import_block + [""] + lines[end:]) + "\n")

# UI fakes must follow the new Collections data-source contract.
replace_required(
    "test/journal/collections_activation_test.dart",
    "  @override\n  Future<String> create({required String title}) async => 'project';\n",
    "  @override\n  Future<String> create({required String title}) async => 'project';\n\n"
    "  @override\n  Future<void> undoCreate(String collectionId) async {}\n",
)

replace_required(
    "test/journal/collections_screen_test.dart",
    "    return id;\n  }\n\n  @override\n  Future<CollectionSnapshot> load(String collectionId) async {\n",
    "    return id;\n  }\n\n"
    "  @override\n  Future<void> undoCreate(String collectionId) async {\n"
    "    _collections.removeWhere((item) => item.id == collectionId);\n"
    "    _entries.remove(collectionId);\n"
    "    _references.remove(collectionId);\n"
    "  }\n\n"
    "  @override\n  Future<CollectionSnapshot> load(String collectionId) async {\n",
)

# Search fakes keep their behavior while accepting the optional signifier
# filter introduced by the data-source contract.
for path_name in (
    "test/journal/search_activation_test.dart",
    "test/journal/search_screen_test.dart",
):
    path = Path(path_name)
    text = path.read_text()
    text = re.sub(
        r"Future<List<JournalSearchResult>> search\(String query\) async \{",
        "Future<List<JournalSearchResult>> search(\n"
        "    String query, {\n"
        "    Set<JournalSignifier> signifiers = const <JournalSignifier>{},\n"
        "  }) async {",
        text,
    )
    text = re.sub(
        r"Future<List<JournalSearchResult>> search\(String query\) \{",
        "Future<List<JournalSearchResult>> search(\n"
        "    String query, {\n"
        "    Set<JournalSignifier> signifiers = const <JournalSignifier>{},\n"
        "  }) {",
        text,
    )
    path.write_text(text)

print("Known analyzer integration issues repaired.")
