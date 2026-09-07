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
    '•' => (marker: '•', type: JournalEntryType.task),
    _ when input.startsWith('• ') => (marker: '•', type: JournalEntryType.task),
    '○' => (marker: '○', type: JournalEntryType.event),
    _ when input.startsWith('○ ') => (
      marker: '○',
      type: JournalEntryType.event,
    ),
    '–' => (marker: '–', type: JournalEntryType.note),
    _ when input.startsWith('– ') => (marker: '–', type: JournalEntryType.note),
    '-' => (marker: '-', type: JournalEntryType.note),
    _ when input.startsWith('- ') => (marker: '-', type: JournalEntryType.note),
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
