import 'package:daymark/core/session/journal_session.dart';
import 'package:daymark/features/journal/data/search_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';

/// Read-only Search access through the serialized unlocked journal session.
extension JournalSearchSession on JournalSession {
  Future<List<JournalSearchResult>> searchJournal(
    String query, {
    Set<JournalSignifier> signifiers = const <JournalSignifier>{},
  }) {
    return run(
      () =>
          JournalSearchRepository(database)
              .search(query, signifiers: signifiers),
    );
  }
}
