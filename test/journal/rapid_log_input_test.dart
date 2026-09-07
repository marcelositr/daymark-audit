import 'package:daymark/features/journal/domain/journal_domain.dart';
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
