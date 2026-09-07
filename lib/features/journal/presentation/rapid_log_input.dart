import 'package:daymark/features/journal/domain/journal_domain.dart';

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
