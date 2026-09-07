import 'package:daymark/features/journal/data/collection_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:daymark/features/journal/presentation/collections_screen.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:daymark/presentation/app_section_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Collections refreshes selected Collection when reactivated', (
    tester,
  ) async {
    final _CollectionsDataSource dataSource = _CollectionsDataSource();
    final ValueNotifier<int> currentSection = ValueNotifier<int>(
      AppSectionScope.collectionsSectionIndex,
    );
    addTearDown(currentSection.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionsJournalDataSourceProvider.overrideWithValue(dataSource),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AppSectionScope(
              currentIndex: currentSection,
              child: const CollectionsScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Project'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Original'), findsOneWidget);

    currentSection.value = 0;
    await tester.pump();
    dataSource.addMigratedTask();
    expect(find.text('Migrated from Today'), findsNothing);

    currentSection.value = AppSectionScope.collectionsSectionIndex;
    await tester.pump();
    await tester.pump();
    expect(find.text('Migrated from Today'), findsOneWidget);
  });

  testWidgets('Collections refreshes references when reactivated', (
    tester,
  ) async {
    final _CollectionsDataSource dataSource = _CollectionsDataSource();
    final ValueNotifier<int> currentSection = ValueNotifier<int>(
      AppSectionScope.collectionsSectionIndex,
    );
    addTearDown(currentSection.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionsJournalDataSourceProvider.overrideWithValue(dataSource),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AppSectionScope(
              currentIndex: currentSection,
              child: const CollectionsScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Project'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Linked elsewhere'), findsNothing);

    currentSection.value = 0;
    await tester.pump();
    dataSource.addReference();
    expect(find.text('Linked elsewhere'), findsNothing);

    currentSection.value = AppSectionScope.collectionsSectionIndex;
    await tester.pump();
    await tester.pump();
    expect(find.text('References'), findsOneWidget);
    expect(find.text('Linked elsewhere'), findsOneWidget);
  });
}

final class _CollectionsDataSource implements CollectionsJournalDataSource {
  final List<CollectionReferenceEntry> references = [];

  final List<CollectionEntry> entries = [
    const CollectionEntry(
      id: 'original',
      type: JournalEntryType.note,
      taskState: null,
      content: 'Original',
      ordinal: 0,
    ),
  ];

  void addMigratedTask() {
    entries.add(
      const CollectionEntry(
        id: 'migrated',
        type: JournalEntryType.task,
        taskState: JournalTaskState.open,
        content: 'Migrated from Today',
        ordinal: 1,
      ),
    );
  }

  void addReference() {
    references.add(
      const CollectionReferenceEntry(
        id: 'linked',
        type: JournalEntryType.note,
        taskState: null,
        content: 'Linked elsewhere',
        ordinal: 0,
      ),
    );
  }

  @override
  Future<List<CollectionSummary>> list() async => const [
    CollectionSummary(id: 'project', title: 'Project'),
  ];

  @override
  Future<String> create({required String title}) async => 'project';

  @override
  Future<void> undoCreate(String collectionId) async {}

  @override
  Future<CollectionSnapshot> load(String collectionId) async =>
      CollectionSnapshot(
        id: 'project',
        title: 'Project',
        entries: entries,
        references: references,
      );

  @override
  Future<void> capture({
    required String collectionId,
    required JournalEntryType type,
    required String content,
  }) async {}

  @override
  Future<void> completeTask({required String entryId}) async {}

  @override
  Future<void> discardTask({required String entryId}) async {}

  @override
  Future<void> removeReference({
    required String collectionId,
    required String entryId,
  }) async {
    references.removeWhere((entry) => entry.id == entryId);
  }
}
