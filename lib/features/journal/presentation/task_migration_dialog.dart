import 'package:daymark/core/session/journal_session.dart';
import 'package:daymark/core/session/journal_session_controller.dart';
import 'package:daymark/features/journal/data/daily_log_repository.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class DailyTaskMigrationDataSource {
  Future<void> migrateTask({
    required String entryId,
    required String methodDate,
  });
}

final Provider<DailyTaskMigrationDataSource> dailyTaskMigrationDataSourceProvider =
    Provider<DailyTaskMigrationDataSource>((ref) {
      final JournalAccessState access = ref
          .watch(journalSessionControllerProvider)
          .requireValue;
      if (access case JournalUnlocked(:final session)) {
        return _SessionDailyTaskMigrationDataSource(session);
      }
      throw StateError(
        'Daily Task migration requires an unlocked journal session.',
      );
    });

final class _SessionDailyTaskMigrationDataSource
    implements DailyTaskMigrationDataSource {
  const _SessionDailyTaskMigrationDataSource(this._session);

  final JournalSession _session;

  @override
  Future<void> migrateTask({
    required String entryId,
    required String methodDate,
  }) {
    return _session.migrateTaskToDaily(
      entryId: entryId,
      methodDate: methodDate,
    );
  }
}

enum TaskMigrationDestination { nextDay, date, collection }

Future<TaskMigrationDestination?> showTaskMigrationDestinationDialog({
  required BuildContext context,
}) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final MaterialLocalizations material = MaterialLocalizations.of(context);

  return showDialog<TaskMigrationDestination>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(l10n.migrateTaskTitle),
      children: <Widget>[
        SimpleDialogOption(
          key: const ValueKey<String>('migrate-next-day'),
          onPressed: () {
            Navigator.of(dialogContext).pop(TaskMigrationDestination.nextDay);
          },
          child: Text(l10n.nextDay),
        ),
        SimpleDialogOption(
          key: const ValueKey<String>('migrate-date'),
          onPressed: () {
            Navigator.of(dialogContext).pop(TaskMigrationDestination.date);
          },
          child: Text(material.datePickerHelpText),
        ),
        SimpleDialogOption(
          key: const ValueKey<String>('migrate-collection'),
          onPressed: () {
            Navigator.of(
              dialogContext,
            ).pop(TaskMigrationDestination.collection);
          },
          child: Text(l10n.collections),
        ),
      ],
    ),
  );
}

String nextTaskMigrationMethodDate(DateTime anchor) {
  final DateTime dateOnly = DateTime(anchor.year, anchor.month, anchor.day);
  return formatJournalMethodDate(dateOnly.add(const Duration(days: 1)));
}

Future<String?> showTaskDailyMigrationDatePicker({
  required BuildContext context,
  required DateTime anchor,
}) async {
  final DateTime dateOnly = DateTime(anchor.year, anchor.month, anchor.day);
  final DateTime firstDate = dateOnly.add(const Duration(days: 1));
  final DateTime? selected = await showDatePicker(
    context: context,
    initialDate: firstDate,
    firstDate: firstDate,
    lastDate: DateTime(9999, 12, 31),
  );
  return selected == null ? null : formatJournalMethodDate(selected);
}
