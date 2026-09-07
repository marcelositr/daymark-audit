from pathlib import Path
import json


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"expected block not found in {path}")
    file.write_text(text.replace(old, new, 1))


def update_arb(path: str, values: dict[str, str]) -> None:
    file = Path(path)
    data = json.loads(file.read_text())
    data.update(values)
    file.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


replace_once(
    "lib/features/journal/domain/journal_domain.dart",
    "enum JournalMigrationKind { migrated, scheduled }\n",
    """enum JournalMigrationKind { migrated, scheduled }\n\nenum JournalSignifier { priority, inspiration, explore }\n""",
)
replace_once(
    "lib/features/journal/domain/journal_domain.dart",
    "extension JournalMigrationKindCode on JournalMigrationKind {\n",
    """extension JournalSignifierCode on JournalSignifier {\n  String get code => switch (this) {\n    JournalSignifier.priority => 'priority',\n    JournalSignifier.inspiration => 'inspiration',\n    JournalSignifier.explore => 'explore',\n  };\n}\n\nJournalSignifier journalSignifierFromCode(String code) => switch (code) {\n  'priority' => JournalSignifier.priority,\n  'inspiration' => JournalSignifier.inspiration,\n  'explore' => JournalSignifier.explore,\n  _ => throw JournalInvariantException('Unknown persisted signifier: $code.'),\n};\n\nextension JournalMigrationKindCode on JournalMigrationKind {\n""",
)

replace_once(
    "lib/features/journal/data/journal_repository.dart",
    "  Future<String> migrateEntry({\n",
    """  Future<Set<JournalSignifier>> listEntrySignifiers({\n    required String entryId,\n  }) async {\n    await _requireEntry(entryId);\n    final rows = await _database\n        .customSelect(\n          '''\n          SELECT s.builtin_code\n          FROM entry_signifiers es\n          JOIN signifiers s ON s.id = es.signifier_id\n          WHERE es.entry_id = ? AND s.kind = 'builtin'\n          ORDER BY s.builtin_code\n          ''',\n          variables: <Variable<Object>>[Variable.withString(entryId)],\n        )\n        .get();\n    return <JournalSignifier>{\n      for (final row in rows)\n        journalSignifierFromCode(row.read<String>('builtin_code')),\n    };\n  }\n\n  Future<void> replaceEntrySignifiers({\n    required String entryId,\n    required Set<JournalSignifier> signifiers,\n  }) {\n    return _database.transaction(() async {\n      await _requireEntry(entryId);\n      final Map<JournalSignifier, String> ids = <JournalSignifier, String>{};\n      for (final JournalSignifier signifier in signifiers) {\n        final existing = await _database\n            .customSelect(\n              '''\n              SELECT id\n              FROM signifiers\n              WHERE kind = 'builtin' AND builtin_code = ?\n              ''',\n              variables: <Variable<Object>>[\n                Variable.withString(signifier.code),\n              ],\n            )\n            .getSingleOrNull();\n        if (existing != null) {\n          ids[signifier] = existing.read<String>('id');\n          continue;\n        }\n        final String id = _newId();\n        await _database.customStatement(\n          '''\n          INSERT INTO signifiers (\n            id, kind, builtin_code, custom_label, custom_symbol, created_at\n          ) VALUES (?, 'builtin', ?, NULL, NULL, ?)\n          ''',\n          <Object>[id, signifier.code, _now()],\n        );\n        ids[signifier] = id;\n      }\n\n      await _database.customStatement(\n        'DELETE FROM entry_signifiers WHERE entry_id = ?',\n        <Object>[entryId],\n      );\n      for (final JournalSignifier signifier in JournalSignifier.values) {\n        final String? signifierId = ids[signifier];\n        if (signifierId == null) {\n          continue;\n        }\n        await _database.customStatement(\n          '''\n          INSERT INTO entry_signifiers (entry_id, signifier_id)\n          VALUES (?, ?)\n          ''',\n          <Object>[entryId, signifierId],\n        );\n      }\n    });\n  }\n\n  Future<String> migrateEntry({\n""",
)
replace_once(
    "lib/features/journal/data/journal_repository.dart",
    """      await _insertPlacement(\n        entryId: destinationEntryId,\n        owner: resolvedDestination,\n        ordinal: destinationOrdinal,\n      );\n\n      if (source.type == JournalEntryType.task) {\n""",
    """      await _insertPlacement(\n        entryId: destinationEntryId,\n        owner: resolvedDestination,\n        ordinal: destinationOrdinal,\n      );\n      await _database.customStatement(\n        '''\n        INSERT INTO entry_signifiers (entry_id, signifier_id)\n        SELECT ?, signifier_id\n        FROM entry_signifiers\n        WHERE entry_id = ?\n        ''',\n        <Object>[destinationEntryId, sourceEntryId],\n      );\n\n      if (source.type == JournalEntryType.task) {\n""",
)

replace_once(
    "lib/features/journal/application/journal_service.dart",
    "  Future<String> migrate({\n",
    """  Future<Set<JournalSignifier>> listEntrySignifiers({\n    required String entryId,\n  }) {\n    return _repository.listEntrySignifiers(entryId: entryId);\n  }\n\n  Future<void> replaceEntrySignifiers({\n    required String entryId,\n    required Set<JournalSignifier> signifiers,\n  }) {\n    return _repository.replaceEntrySignifiers(\n      entryId: entryId,\n      signifiers: signifiers,\n    );\n  }\n\n  Future<String> migrate({\n""",
)

replace_once(
    "lib/features/journal/data/monthly_log_repository.dart",
    "  Future<void> captureTask({required String logId, required String content}) {\n",
    """  Future<void> captureCalendarTask({\n    required String logId,\n    required String calendarDate,\n    required String content,\n  }) {\n    return _journalService.capture(\n      type: JournalEntryType.task,\n      content: content,\n      owner: JournalLogOwner(\n        logId: logId,\n        monthlySection: JournalMonthlySection.calendar,\n        monthlyCalendarDate: calendarDate,\n      ),\n    );\n  }\n\n  Future<void> captureTask({required String logId, required String content}) {\n""",
)

replace_once(
    "lib/features/journal/data/future_log_repository.dart",
    """    required this.ordinal,\n  });\n\n  final String id;\n""",
    """    required this.ordinal,\n    this.hasOutgoingMigration = false,\n  });\n\n  final String id;\n""",
)
replace_once(
    "lib/features/journal/data/future_log_repository.dart",
    """  final int ordinal;\n}\n""",
    """  final int ordinal;\n  final bool hasOutgoingMigration;\n}\n""",
)
replace_once(
    "lib/features/journal/data/future_log_repository.dart",
    """            e.content,\n            p.ordinal\n          FROM entry_placements p\n          JOIN entries e ON e.id = p.entry_id\n          WHERE p.log_id = ?\n""",
    """            e.content,\n            p.ordinal,\n            CASE WHEN m.source_entry_id IS NULL THEN 0 ELSE 1 END\n              AS has_outgoing_migration\n          FROM entry_placements p\n          JOIN entries e ON e.id = p.entry_id\n          LEFT JOIN migrations m ON m.source_entry_id = e.id\n          WHERE p.log_id = ?\n""",
)
replace_once(
    "lib/features/journal/data/future_log_repository.dart",
    """          ordinal: row.read<int>('ordinal'),\n        ),\n""",
    """          ordinal: row.read<int>('ordinal'),\n          hasOutgoingMigration: row.read<int>('has_outgoing_migration') != 0,\n        ),\n""",
)

replace_once(
    "lib/core/session/journal_session.dart",
    "  Future<void> captureMonthlyTask({\n",
    """  Future<void> captureMonthlyCalendarTask({\n    required String logId,\n    required String calendarDate,\n    required String content,\n  }) {\n    return run(\n      () => monthlyLog.captureCalendarTask(\n        logId: logId,\n        calendarDate: calendarDate,\n        content: content,\n      ),\n    );\n  }\n\n  Future<void> captureMonthlyTask({\n""",
)
replace_once(
    "lib/core/session/journal_session.dart",
    "  Future<void> migrateTaskToDaily({\n",
    """  Future<Set<JournalSignifier>> listEntrySignifiers({\n    required String entryId,\n  }) {\n    return run(() => service.listEntrySignifiers(entryId: entryId));\n  }\n\n  Future<void> replaceEntrySignifiers({\n    required String entryId,\n    required Set<JournalSignifier> signifiers,\n  }) {\n    return run(\n      () => service.replaceEntrySignifiers(\n        entryId: entryId,\n        signifiers: signifiers,\n      ),\n    );\n  }\n\n  Future<void> migrateTaskToDaily({\n""",
)
replace_once(
    "lib/core/session/journal_session.dart",
    "  Future<void> migrateTaskToCollection({\n",
    """  Future<void> migrateFutureEventToMonthlyCalendar({\n    required String entryId,\n    required String periodStart,\n    required String calendarDate,\n  }) {\n    return run(() async {\n      validateJournalMonthStart(periodStart);\n      validateJournalMethodDate(calendarDate);\n      await _requireFutureEventCalendarDestination(\n        entryId: entryId,\n        periodStart: periodStart,\n        calendarDate: calendarDate,\n      );\n      final MonthlyLogSnapshot destination = await monthlyLog.loadOrCreate(\n        periodStart,\n      );\n      await service.migrate(\n        sourceEntryId: entryId,\n        destinationOwner: JournalLogOwner(\n          logId: destination.logId,\n          monthlySection: JournalMonthlySection.calendar,\n          monthlyCalendarDate: calendarDate,\n        ),\n      );\n    });\n  }\n\n  Future<void> migrateTaskToCollection({\n""",
)
replace_once(
    "lib/core/session/journal_session.dart",
    "  Future<void> close() async {\n",
    """  Future<void> _requireFutureEventCalendarDestination({\n    required String entryId,\n    required String periodStart,\n    required String calendarDate,\n  }) async {\n    if (!calendarDate.startsWith(periodStart.substring(0, 7))) {\n      throw const JournalInvariantException(\n        'Future Event migration must choose a day in the matching month.',\n      );\n    }\n    final row = await database\n        .customSelect(\n          '''\n          SELECT e.entry_type, l.kind, l.period_start,\n                 CASE WHEN m.source_entry_id IS NULL THEN 0 ELSE 1 END\n                   AS has_outgoing_migration\n          FROM entries e\n          JOIN entry_placements p ON p.entry_id = e.id\n          LEFT JOIN logs l ON l.id = p.log_id\n          LEFT JOIN migrations m ON m.source_entry_id = e.id\n          WHERE e.id = ?\n          ''',\n          variables: <Variable<Object>>[Variable.withString(entryId)],\n        )\n        .getSingleOrNull();\n    if (row == null) {\n      throw JournalNotFoundException('Entry', entryId);\n    }\n    if (row.read<String>('entry_type') != JournalEntryType.event.code ||\n        row.readNullable<String>('kind') != JournalLogKind.future.code ||\n        row.readNullable<String>('period_start') != periodStart) {\n      throw const JournalInvariantException(\n        'Monthly Calendar migration requires an Event from the matching Future Log.',\n      );\n    }\n    if (row.read<int>('has_outgoing_migration') != 0) {\n      throw const JournalInvariantException(\n        'An entry may have only one direct outgoing migration.',\n      );\n    }\n  }\n\n  Future<void> close() async {\n""",
)

Path("lib/features/journal/presentation/monthly_calendar_task_data_source.dart").write_text(
    """import 'package:daymark/core/session/journal_session.dart';\nimport 'package:daymark/core/session/journal_session_controller.dart';\nimport 'package:flutter_riverpod/flutter_riverpod.dart';\n\nabstract interface class MonthlyCalendarTaskDataSource {\n  Future<void> capture({\n    required String logId,\n    required String calendarDate,\n    required String content,\n  });\n}\n\nfinal Provider<MonthlyCalendarTaskDataSource> monthlyCalendarTaskDataSourceProvider =\n    Provider<MonthlyCalendarTaskDataSource>((ref) {\n      final JournalAccessState access = ref\n          .watch(journalSessionControllerProvider)\n          .requireValue;\n      if (access case JournalUnlocked(:final session)) {\n        return _SessionMonthlyCalendarTaskDataSource(session);\n      }\n      throw StateError(\n        'Monthly Calendar Task capture requires an unlocked journal session.',\n      );\n    });\n\nfinal class _SessionMonthlyCalendarTaskDataSource\n    implements MonthlyCalendarTaskDataSource {\n  const _SessionMonthlyCalendarTaskDataSource(this._session);\n\n  final JournalSession _session;\n\n  @override\n  Future<void> capture({\n    required String logId,\n    required String calendarDate,\n    required String content,\n  }) {\n    return _session.captureMonthlyCalendarTask(\n      logId: logId,\n      calendarDate: calendarDate,\n      content: content,\n    );\n  }\n}\n"""
)

Path("lib/features/journal/presentation/future_event_migration_data_source.dart").write_text(
    """import 'package:daymark/core/session/journal_session.dart';\nimport 'package:daymark/core/session/journal_session_controller.dart';\nimport 'package:flutter_riverpod/flutter_riverpod.dart';\n\nabstract interface class FutureEventMigrationDataSource {\n  Future<void> migrateToMonthlyCalendar({\n    required String entryId,\n    required String periodStart,\n    required String calendarDate,\n  });\n}\n\nfinal Provider<FutureEventMigrationDataSource> futureEventMigrationDataSourceProvider =\n    Provider<FutureEventMigrationDataSource>((ref) {\n      final JournalAccessState access = ref\n          .watch(journalSessionControllerProvider)\n          .requireValue;\n      if (access case JournalUnlocked(:final session)) {\n        return _SessionFutureEventMigrationDataSource(session);\n      }\n      throw StateError(\n        'Future Event migration requires an unlocked journal session.',\n      );\n    });\n\nfinal class _SessionFutureEventMigrationDataSource\n    implements FutureEventMigrationDataSource {\n  const _SessionFutureEventMigrationDataSource(this._session);\n\n  final JournalSession _session;\n\n  @override\n  Future<void> migrateToMonthlyCalendar({\n    required String entryId,\n    required String periodStart,\n    required String calendarDate,\n  }) {\n    return _session.migrateFutureEventToMonthlyCalendar(\n      entryId: entryId,\n      periodStart: periodStart,\n      calendarDate: calendarDate,\n    );\n  }\n}\n"""
)

Path("lib/features/journal/presentation/entry_signifiers.dart").write_text(
    """import 'package:daymark/core/session/journal_session.dart';\nimport 'package:daymark/core/session/journal_session_controller.dart';\nimport 'package:daymark/features/journal/domain/journal_domain.dart';\nimport 'package:daymark/l10n/app_localizations.dart';\nimport 'package:flutter/material.dart';\nimport 'package:flutter_riverpod/flutter_riverpod.dart';\n\nabstract interface class EntrySignifierDataSource {\n  Future<Set<JournalSignifier>> list({required String entryId});\n\n  Future<void> replace({\n    required String entryId,\n    required Set<JournalSignifier> signifiers,\n  });\n}\n\nfinal Provider<EntrySignifierDataSource> entrySignifierDataSourceProvider =\n    Provider<EntrySignifierDataSource>((ref) {\n      final JournalAccessState access = ref\n          .watch(journalSessionControllerProvider)\n          .requireValue;\n      if (access case JournalUnlocked(:final session)) {\n        return _SessionEntrySignifierDataSource(session);\n      }\n      throw StateError('Signifiers require an unlocked journal session.');\n    });\n\nfinal FutureProviderFamily<Set<JournalSignifier>, String> entrySignifiersProvider =\n    FutureProvider.family<Set<JournalSignifier>, String>((ref, entryId) {\n      return ref.watch(entrySignifierDataSourceProvider).list(entryId: entryId);\n    });\n\nfinal class _SessionEntrySignifierDataSource implements EntrySignifierDataSource {\n  const _SessionEntrySignifierDataSource(this._session);\n\n  final JournalSession _session;\n\n  @override\n  Future<Set<JournalSignifier>> list({required String entryId}) {\n    return _session.listEntrySignifiers(entryId: entryId);\n  }\n\n  @override\n  Future<void> replace({\n    required String entryId,\n    required Set<JournalSignifier> signifiers,\n  }) {\n    return _session.replaceEntrySignifiers(\n      entryId: entryId,\n      signifiers: signifiers,\n    );\n  }\n}\n\nclass EntrySignifierMarks extends ConsumerWidget {\n  const EntrySignifierMarks({required this.entryId, super.key});\n\n  final String entryId;\n\n  @override\n  Widget build(BuildContext context, WidgetRef ref) {\n    final AsyncValue<Set<JournalSignifier>> value = ref.watch(\n      entrySignifiersProvider(entryId),\n    );\n    return value.maybeWhen(\n      data: (signifiers) {\n        final String marks = _marks(signifiers);\n        if (marks.isEmpty) {\n          return const SizedBox.shrink();\n        }\n        return Padding(\n          padding: const EdgeInsetsDirectional.only(end: 6),\n          child: Text(marks, style: Theme.of(context).textTheme.labelMedium),\n        );\n      },\n      orElse: () => const SizedBox.shrink(),\n    );\n  }\n}\n\nFuture<bool> showEntrySignifierDialog({\n  required BuildContext context,\n  required WidgetRef ref,\n  required String entryId,\n}) async {\n  final EntrySignifierDataSource dataSource = ref.read(\n    entrySignifierDataSourceProvider,\n  );\n  final Set<JournalSignifier> initial = await dataSource.list(entryId: entryId);\n  if (!context.mounted) {\n    return false;\n  }\n  final Set<JournalSignifier>? selected = await showDialog<Set<JournalSignifier>>(\n    context: context,\n    builder: (dialogContext) {\n      final Set<JournalSignifier> draft = <JournalSignifier>{...initial};\n      return StatefulBuilder(\n        builder: (context, setDialogState) {\n          final AppLocalizations l10n = AppLocalizations.of(context);\n          return AlertDialog(\n            title: Text(l10n.signifiers),\n            content: Column(\n              mainAxisSize: MainAxisSize.min,\n              children: [\n                _tile(\n                  context: context,\n                  signifier: JournalSignifier.priority,\n                  label: l10n.signifierPriority,\n                  symbol: '*',\n                  draft: draft,\n                  setDialogState: setDialogState,\n                ),\n                _tile(\n                  context: context,\n                  signifier: JournalSignifier.inspiration,\n                  label: l10n.signifierInspiration,\n                  symbol: '!',\n                  draft: draft,\n                  setDialogState: setDialogState,\n                ),\n                _tile(\n                  context: context,\n                  signifier: JournalSignifier.explore,\n                  label: l10n.signifierExplore,\n                  symbol: '◉',\n                  draft: draft,\n                  setDialogState: setDialogState,\n                ),\n              ],\n            ),\n            actions: [\n              TextButton(\n                onPressed: () => Navigator.of(dialogContext).pop(),\n                child: Text(MaterialLocalizations.of(context).cancelButtonLabel),\n              ),\n              FilledButton(\n                onPressed: () => Navigator.of(dialogContext).pop(\n                  <JournalSignifier>{...draft},\n                ),\n                child: Text(MaterialLocalizations.of(context).saveButtonLabel),\n              ),\n            ],\n          );\n        },\n      );\n    },\n  );\n  if (selected == null) {\n    return false;\n  }\n  await dataSource.replace(entryId: entryId, signifiers: selected);\n  ref.invalidate(entrySignifiersProvider(entryId));\n  return true;\n}\n\nWidget _tile({\n  required BuildContext context,\n  required JournalSignifier signifier,\n  required String label,\n  required String symbol,\n  required Set<JournalSignifier> draft,\n  required StateSetter setDialogState,\n}) {\n  return CheckboxListTile(\n    value: draft.contains(signifier),\n    onChanged: (value) {\n      setDialogState(() {\n        if (value ?? false) {\n          draft.add(signifier);\n        } else {\n          draft.remove(signifier);\n        }\n      });\n    },\n    contentPadding: EdgeInsets.zero,\n    title: Text(label),\n    secondary: SizedBox(\n      width: 24,\n      child: Text(\n        symbol,\n        textAlign: TextAlign.center,\n        style: Theme.of(context).textTheme.titleMedium,\n      ),\n    ),\n  );\n}\n\nString _marks(Set<JournalSignifier> signifiers) => <String>[\n  if (signifiers.contains(JournalSignifier.priority)) '*',\n  if (signifiers.contains(JournalSignifier.inspiration)) '!',\n  if (signifiers.contains(JournalSignifier.explore)) '◉',\n].join();\n"""
)

translations = {
    "lib/l10n/app_en.arb": {
        "monthlyCalendarTaskHint": "Add a task for this day",
        "signifiers": "Signifiers",
        "signifierPriority": "Priority",
        "signifierInspiration": "Inspiration",
        "signifierExplore": "Explore",
        "signifierUpdateFailed": "Could not update signifiers.",
        "reviewCurrentFutureLog": "Review arrived Future entries",
        "futureArrivalReviewPrompt": "This Future Log month has arrived. Review open Tasks and Events deliberately. Tasks can move to Monthly Tasks, complete, or discard; Events can move to a chosen day in the Monthly Calendar.",
        "migrateEventToCalendar": "Move to Monthly Calendar",
        "eventMigrationFailed": "Could not migrate this event."
    },
    "lib/l10n/app_pt_BR.arb": {
        "monthlyCalendarTaskHint": "Adicione uma tarefa para este dia",
        "signifiers": "Significadores",
        "signifierPriority": "Prioridade",
        "signifierInspiration": "Inspiração",
        "signifierExplore": "Explorar",
        "signifierUpdateFailed": "Não foi possível atualizar os significadores.",
        "reviewCurrentFutureLog": "Revisar entradas do Future que chegaram",
        "futureArrivalReviewPrompt": "Este mês do Future Log chegou. Revise Tasks e Events em aberto de forma deliberada. Tasks podem ir para Monthly Tasks, ser concluídas ou descartadas; Events podem ir para um dia escolhido no Monthly Calendar.",
        "migrateEventToCalendar": "Mover para o Monthly Calendar",
        "eventMigrationFailed": "Não foi possível migrar este evento."
    },
    "lib/l10n/app_pt.arb": {
        "monthlyCalendarTaskHint": "Adicione uma tarefa para este dia",
        "signifiers": "Significadores",
        "signifierPriority": "Prioridade",
        "signifierInspiration": "Inspiração",
        "signifierExplore": "Explorar",
        "signifierUpdateFailed": "Não foi possível atualizar os significadores.",
        "reviewCurrentFutureLog": "Rever entradas do Future que chegaram",
        "futureArrivalReviewPrompt": "Este mês do Future Log chegou. Reveja Tasks e Events em aberto de forma deliberada. Tasks podem ir para Monthly Tasks, ser concluídas ou descartadas; Events podem ir para um dia escolhido no Monthly Calendar.",
        "migrateEventToCalendar": "Mover para o Monthly Calendar",
        "eventMigrationFailed": "Não foi possível migrar este evento."
    },
    "lib/l10n/app_es.arb": {
        "monthlyCalendarTaskHint": "Añade una tarea para este día",
        "signifiers": "Significadores",
        "signifierPriority": "Prioridad",
        "signifierInspiration": "Inspiración",
        "signifierExplore": "Explorar",
        "signifierUpdateFailed": "No se pudieron actualizar los significadores.",
        "reviewCurrentFutureLog": "Revisar entradas de Future que llegaron",
        "futureArrivalReviewPrompt": "Este mes del Future Log ha llegado. Revisa deliberadamente las Tasks y Events pendientes. Las Tasks pueden pasar a Monthly Tasks, completarse o descartarse; los Events pueden pasar a un día elegido del Monthly Calendar.",
        "migrateEventToCalendar": "Mover al Monthly Calendar",
        "eventMigrationFailed": "No se pudo migrar este evento."
    }
}
for path, values in translations.items():
    update_arb(path, values)

for path, section in {
    "docs/DOMAIN.md": """\n## Experimental Bullet Journal fidelity extensions\n\nOn the isolated `feat/daily-task-migration` branch, the maintainer has explicitly approved evaluation of additional method-native semantics beyond the frozen baseline:\n\n- Monthly Calendar may own dated Task entries as well as Events;\n- an arrived Future Event may migrate deliberately into the matching Monthly Calendar after the user chooses a day;\n- built-in Signifiers (`priority`, `inspiration`, `explore`) are user-visible optional Entry context;\n- Signifiers follow a migrated Entry to its fresh destination while remaining attached to the historical source;\n- an Event with outgoing migration lineage is considered resolved for Future arrival review even though Events do not acquire Task state.\n\nThese rules remain experimental until this PR is explicitly promoted into the main Daymark product.\n""",
    "docs/PRODUCT.md": """\n## Experimental Bullet Journal fidelity extensions\n\nThe isolated `feat/daily-task-migration` branch additionally evaluates three method-native capabilities explicitly approved by the maintainer:\n\n- dated Tasks in the Monthly Calendar, alongside Events;\n- deliberate Future Event arrival migration into a user-selected day of the matching Monthly Calendar;\n- optional built-in Signifiers for Priority, Inspiration, and Explore.\n\nThese additions preserve Daymark's minimalism: there is no automatic rollover, no guessed Event date, no new planner abstraction, and no custom Signifier system. They remain experimental until the maintainer explicitly promotes this PR.\n"""
}.items():
    file = Path(path)
    text = file.read_text()
    if "## Experimental Bullet Journal fidelity extensions" not in text:
        file.write_text(text.rstrip() + "\n" + section)

experiment = Path("docs/DAILY_TASK_MIGRATION_EXPERIMENT.md")
text = experiment.read_text()
if "## Dated Monthly Calendar Tasks" not in text:
    experiment.write_text(text.rstrip() + """\n\n## Dated Monthly Calendar Tasks\n\nThe current Monthly Calendar may deliberately capture either an Event or a dated Task for a selected day. A dated Task remains a real Task with the normal Task lifecycle; the date belongs to its Monthly Calendar placement rather than becoming hidden Task metadata.\n\nThis does not turn Monthly into a general planner. The Calendar remains one row per day and accepts only method-native Events and Tasks.\n\n## Future Event arrival\n\nWhen a Future Log month arrives, an Event that has not already moved may be deliberately migrated into the matching Monthly Calendar. Because Future is month-addressed, the user must explicitly choose the calendar day during migration. No day is guessed automatically.\n\nThe source Future Event remains historical. The destination is a fresh Monthly Calendar Event with its own identity and migration lineage.\n\n## Signifiers\n\nDaymark exposes the three built-in optional Bullet Journal Signifiers already represented by the encrypted schema: `*` Priority, `!` Inspiration, and `◉` Explore. Signifiers remain optional context, never Entry types or Task states. Migration copies them to the fresh destination Entry while preserving them on the historical source. No custom Signifier UI is introduced.\n""")

print("core fidelity changes staged")
