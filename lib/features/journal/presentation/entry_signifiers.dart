import 'package:daymark/core/session/journal_session.dart';
import 'package:daymark/core/session/journal_session_controller.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class EntrySignifierDataSource {
  Future<Set<JournalSignifier>> list({required String entryId});

  Future<void> replace({
    required String entryId,
    required Set<JournalSignifier> signifiers,
  });
}

final Provider<EntrySignifierDataSource> entrySignifierDataSourceProvider =
    Provider<EntrySignifierDataSource>((ref) {
      final JournalAccessState access = ref
          .watch(journalSessionControllerProvider)
          .requireValue;
      if (access case JournalUnlocked(:final session)) {
        return _SessionEntrySignifierDataSource(session);
      }
      throw StateError('Signifiers require an unlocked journal session.');
    });

final entrySignifiersProvider =
    FutureProvider.family<Set<JournalSignifier>, String>((ref, entryId) {
      return ref.watch(entrySignifierDataSourceProvider).list(entryId: entryId);
    });

final class _SessionEntrySignifierDataSource
    implements EntrySignifierDataSource {
  const _SessionEntrySignifierDataSource(this._session);

  final JournalSession _session;

  @override
  Future<Set<JournalSignifier>> list({required String entryId}) {
    return _session.listEntrySignifiers(entryId: entryId);
  }

  @override
  Future<void> replace({
    required String entryId,
    required Set<JournalSignifier> signifiers,
  }) {
    return _session.replaceEntrySignifiers(
      entryId: entryId,
      signifiers: signifiers,
    );
  }
}

const double signifierColumnWidth = 44;

class SignifierMarks extends StatelessWidget {
  const SignifierMarks({required this.signifiers, super.key});

  final Set<JournalSignifier> signifiers;

  @override
  Widget build(BuildContext context) {
    final String marks = _marks(signifiers);
    return SizedBox(
      width: signifierColumnWidth,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: marks.isEmpty
              ? const SizedBox.shrink()
              : ExcludeSemantics(
                  child: Text(
                    marks,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
        ),
      ),
    );
  }
}

class EntrySignifierMarks extends ConsumerWidget {
  const EntrySignifierMarks({required this.entryId, super.key});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Set<JournalSignifier>> value = ref.watch(
      entrySignifiersProvider(entryId),
    );
    return SignifierMarks(
      signifiers:
          value.maybeWhen(data: (value) => value, orElse: () => null) ??
          const <JournalSignifier>{},
    );
  }
}

Future<bool> showEntrySignifierDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String entryId,
}) async {
  final EntrySignifierDataSource dataSource = ref.read(
    entrySignifierDataSourceProvider,
  );
  final Set<JournalSignifier> initial = await dataSource.list(entryId: entryId);
  if (!context.mounted) {
    return false;
  }
  final Set<JournalSignifier>? selected =
      await showDialog<Set<JournalSignifier>>(
        context: context,
        builder: (dialogContext) {
          final Set<JournalSignifier> draft = <JournalSignifier>{...initial};
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final AppLocalizations l10n = AppLocalizations.of(context);
              return AlertDialog(
                title: Text(l10n.signifiers),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _tile(
                      context: context,
                      signifier: JournalSignifier.priority,
                      label: l10n.signifierPriority,
                      symbol: '*',
                      draft: draft,
                      setDialogState: setDialogState,
                    ),
                    _tile(
                      context: context,
                      signifier: JournalSignifier.inspiration,
                      label: l10n.signifierInspiration,
                      symbol: '!',
                      draft: draft,
                      setDialogState: setDialogState,
                    ),
                    _tile(
                      context: context,
                      signifier: JournalSignifier.explore,
                      label: l10n.signifierExplore,
                      symbol: '◉',
                      draft: draft,
                      setDialogState: setDialogState,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(
                      MaterialLocalizations.of(context).cancelButtonLabel,
                    ),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(dialogContext)
                            .pop(<JournalSignifier>{...draft}),
                    child: Text(
                      MaterialLocalizations.of(context).saveButtonLabel,
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
  if (selected == null) {
    return false;
  }
  await dataSource.replace(entryId: entryId, signifiers: selected);
  ref.invalidate(entrySignifiersProvider(entryId));
  return true;
}

Widget _tile({
  required BuildContext context,
  required JournalSignifier signifier,
  required String label,
  required String symbol,
  required Set<JournalSignifier> draft,
  required StateSetter setDialogState,
}) {
  return CheckboxListTile(
    value: draft.contains(signifier),
    onChanged: (value) {
      setDialogState(() {
        if (value ?? false) {
          draft.add(signifier);
        } else {
          draft.remove(signifier);
        }
      });
    },
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    secondary: SizedBox(
      width: 24,
      child: Text(
        symbol,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
  );
}

String _marks(Set<JournalSignifier> signifiers) => <String>[
  if (signifiers.contains(JournalSignifier.priority)) '*',
  if (signifiers.contains(JournalSignifier.inspiration)) '!',
  if (signifiers.contains(JournalSignifier.explore)) '◉',
].join();
