import 'package:daymark/features/journal/data/journal_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';

/// Application boundary for intentional Bullet Journal operations.
///
/// Presentation code should call this service instead of coordinating multiple
/// persistence writes itself. Repository methods remain transactional and own
/// the cross-table persistence invariants.
final class JournalService {
  const JournalService(this._repository);

  final JournalRepository _repository;

  Future<String> createLog({
    required JournalLogKind kind,
    required String periodStart,
  }) {
    return _repository.createLog(kind: kind, periodStart: periodStart);
  }

  Future<String> createCollection({required String title}) {
    return _repository.createCollection(title: title);
  }

  Future<void> undoCollectionCreation({required String collectionId}) {
    return _repository.undoCollectionCreation(collectionId: collectionId);
  }

  Future<String> capture({
    required JournalEntryType type,
    required String content,
    required JournalEntryOwner owner,
  }) {
    return _repository.createEntry(type: type, content: content, owner: owner);
  }

  Future<void> undoCapture({required String entryId}) {
    return _repository.undoCapture(entryId: entryId);
  }

  Future<void> referenceInCollection({
    required String collectionId,
    required String entryId,
  }) {
    return _repository.addCollectionReference(
      collectionId: collectionId,
      entryId: entryId,
    );
  }

  Future<void> removeReferenceFromCollection({
    required String collectionId,
    required String entryId,
  }) {
    return _repository.removeCollectionReference(
      collectionId: collectionId,
      entryId: entryId,
    );
  }

  Future<Set<JournalSignifier>> listEntrySignifiers({required String entryId}) {
    return _repository.listEntrySignifiers(entryId: entryId);
  }

  Future<void> replaceEntrySignifiers({
    required String entryId,
    required Set<JournalSignifier> signifiers,
  }) {
    return _repository.replaceEntrySignifiers(
      entryId: entryId,
      signifiers: signifiers,
    );
  }

  Future<String> migrate({
    required String sourceEntryId,
    required JournalEntryOwner destinationOwner,
  }) {
    return _repository.migrateEntry(
      sourceEntryId: sourceEntryId,
      destinationOwner: destinationOwner,
      kind: JournalMigrationKind.migrated,
    );
  }

  Future<String> schedule({
    required String sourceEntryId,
    required JournalLogOwner futureLogOwner,
  }) {
    return _repository.migrateEntry(
      sourceEntryId: sourceEntryId,
      destinationOwner: futureLogOwner,
      kind: JournalMigrationKind.scheduled,
    );
  }
}
