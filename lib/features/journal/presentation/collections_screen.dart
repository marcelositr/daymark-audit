import 'dart:async';

import 'package:daymark/core/session/journal_session.dart';
import 'package:daymark/core/session/journal_session_controller.dart';
import 'package:daymark/features/journal/data/collection_repository.dart';
import 'package:daymark/features/journal/domain/journal_domain.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:daymark/presentation/app_section_scope.dart';
import 'package:daymark/presentation/daymark_empty_state.dart';
import 'package:daymark/presentation/daymark_notice.dart';
import 'package:daymark/presentation/daymark_page_frame.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'entry_capture_undo.dart';
import 'entry_semantics.dart';
import 'entry_signifiers.dart';
import 'journal_activity_guard.dart';
import 'rapid_log_input.dart';

abstract interface class CollectionsJournalDataSource {
  Future<List<CollectionSummary>> list();

  Future<String> create({required String title});

  Future<void> undoCreate(String collectionId);

  Future<CollectionSnapshot> load(String collectionId);

  Future<void> capture({
    required String collectionId,
    required JournalEntryType type,
    required String content,
  });

  Future<void> completeTask({required String entryId});

  Future<void> discardTask({required String entryId});

  Future<void> removeReference({
    required String collectionId,
    required String entryId,
  });
}

final Provider<CollectionsJournalDataSource>
collectionsJournalDataSourceProvider = Provider<CollectionsJournalDataSource>((
  ref,
) {
  final JournalAccessState access = ref
      .watch(journalSessionControllerProvider)
      .requireValue;
  if (access case JournalUnlocked(:final session)) {
    return _SessionCollectionsJournalDataSource(session);
  }
  throw StateError('Collections requires an unlocked journal session.');
});

final class _SessionCollectionsJournalDataSource
    implements CollectionsJournalDataSource {
  const _SessionCollectionsJournalDataSource(this._session);

  final JournalSession _session;

  @override
  Future<List<CollectionSummary>> list() => _session.listCollections();

  @override
  Future<String> create({required String title}) {
    return _session.createCollection(title: title);
  }

  @override
  Future<void> undoCreate(String collectionId) {
    return _session.undoCollectionCreation(collectionId: collectionId);
  }

  @override
  Future<CollectionSnapshot> load(String collectionId) {
    return _session.loadCollection(collectionId);
  }

  @override
  Future<void> capture({
    required String collectionId,
    required JournalEntryType type,
    required String content,
  }) {
    return _session.captureCollectionEntry(
      collectionId: collectionId,
      type: type,
      content: content,
    );
  }

  @override
  Future<void> completeTask({required String entryId}) {
    return _session.completeTask(entryId: entryId);
  }

  @override
  Future<void> discardTask({required String entryId}) {
    return _session.discardTask(entryId: entryId);
  }

  @override
  Future<void> removeReference({
    required String collectionId,
    required String entryId,
  }) {
    return _session.removeEntryReferenceFromCollection(
      collectionId: collectionId,
      entryId: entryId,
    );
  }
}

class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({this.initialCollectionId, super.key});

  final String? initialCollectionId;

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _entryController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _entryFocusNode = FocusNode();

  late Future<List<CollectionSummary>> _collectionsFuture;
  Future<CollectionSnapshot>? _collectionFuture;
  String? _selectedCollectionId;
  JournalEntryType _entryType = JournalEntryType.task;
  bool _saving = false;
  String? _taskActionEntryId;
  bool _sectionScopeInitialized = false;
  bool _wasCollectionsSectionActive = false;

  @override
  void initState() {
    super.initState();
    _selectedCollectionId = widget.initialCollectionId;
    _collectionsFuture = _dataSource().list();
    final String? collectionId = _selectedCollectionId;
    if (collectionId != null) {
      _collectionFuture = _dataSource().load(collectionId);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final int? currentSectionIndex = AppSectionScope.maybeCurrentIndexOf(
      context,
    );
    if (currentSectionIndex == null) {
      return;
    }

    final bool isCollectionsSectionActive =
        currentSectionIndex == AppSectionScope.collectionsSectionIndex;
    if (_sectionScopeInitialized &&
        isCollectionsSectionActive &&
        !_wasCollectionsSectionActive) {
      _collectionsFuture = _dataSource().list();
      final String? collectionId = _selectedCollectionId;
      if (collectionId != null) {
        _collectionFuture = _dataSource().load(collectionId);
      }
      _restoreActiveFocus();
    }
    _sectionScopeInitialized = true;
    _wasCollectionsSectionActive = isCollectionsSectionActive;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _entryController.dispose();
    _titleFocusNode.dispose();
    _entryFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return DaymarkPageFrame(
      child: _selectedCollectionId == null
          ? _buildCollectionList(l10n)
          : _buildCollection(l10n),
    );
  }

  Widget _buildCollectionList(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.collections,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              onPressed: _lock,
              tooltip: l10n.lockJournal,
              icon: const Icon(Icons.lock_outline),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: FutureBuilder<List<CollectionSummary>>(
            future: _collectionsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return Center(child: Text(l10n.collectionsLoadFailed));
              }
              final collections = snapshot.requireData;
              if (collections.isEmpty) {
                return DaymarkEmptyState(message: l10n.emptyCollections);
              }
              return ListView.separated(
                itemCount: collections.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final CollectionSummary collection = collections[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(collection.title),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _saving ? null : () => _open(collection.id),
                  );
                },
              );
            },
          ),
        ),
        const DaymarkNoticeRegion(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _titleController,
                focusNode: _titleFocusNode,
                autofocus:
                    defaultTargetPlatform == TargetPlatform.linux &&
                    _selectedCollectionId == null,
                enabled: !_saving,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_createCollection()),
                onChanged: (_) => JournalActivityGuard.recordActivity(context),
                decoration: InputDecoration(
                  hintText: l10n.collectionTitleHint,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _saving ? null : _createCollection,
              tooltip: l10n.createCollection,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCollection(AppLocalizations l10n) {
    return FutureBuilder<CollectionSnapshot>(
      future: _collectionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(child: Text(l10n.collectionLoadFailed));
        }
        final CollectionSnapshot collection = snapshot.requireData;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _saving ? null : _backToList,
                  tooltip: l10n.backToCollections,
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    collection.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  onPressed: _lock,
                  tooltip: l10n.lockJournal,
                  icon: const Icon(Icons.lock_outline),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildCollectionContent(l10n, collection)),
            const DaymarkNoticeRegion(),
            const SizedBox(height: 12),
            SegmentedButton<JournalEntryType>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: JournalEntryType.task,
                  label: Text(l10n.entryTask),
                ),
                ButtonSegment(
                  value: JournalEntryType.event,
                  label: Text(l10n.entryEvent),
                ),
                ButtonSegment(
                  value: JournalEntryType.note,
                  label: Text(l10n.entryNote),
                ),
              ],
              selected: <JournalEntryType>{_entryType},
              onSelectionChanged: _saving
                  ? null
                  : (selection) {
                      setState(() => _entryType = selection.single);
                      _restoreActiveFocus();
                    },
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Focus(
                    onKeyEvent: _handleEntryComposerKeyEvent,
                    child: TextField(
                      controller: _entryController,
                      focusNode: _entryFocusNode,
                      autofocus:
                          defaultTargetPlatform == TargetPlatform.linux &&
                          _selectedCollectionId != null,
                      enabled: !_saving,
                      minLines: 1,
                      maxLines: 4,
                      onChanged: (_) =>
                          JournalActivityGuard.recordActivity(context),
                      decoration: InputDecoration(
                        hintText: l10n.collectionEntryHint,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _saving ? null : _capture,
                  tooltip: l10n.addEntry,
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildCollectionContent(
    AppLocalizations l10n,
    CollectionSnapshot collection,
  ) {
    if (collection.entries.isEmpty && collection.references.isEmpty) {
      return DaymarkEmptyState(message: l10n.emptyCollection);
    }

    return ListView(
      children: [
        for (int index = 0; index < collection.entries.length; index++)
          Padding(
            padding: EdgeInsets.only(
              bottom: index == collection.entries.length - 1 ? 0 : 6,
            ),
            child: _buildEntry(l10n, collection.entries[index]),
          ),
        if (collection.references.isNotEmpty) ...[
          if (collection.entries.isNotEmpty) const SizedBox(height: 20),
          Text(
            l10n.collectionReferences,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (int index = 0; index < collection.references.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == collection.references.length - 1 ? 0 : 6,
              ),
              child: _buildReference(l10n, collection.references[index]),
            ),
        ],
      ],
    );
  }

  Widget _buildReference(
    AppLocalizations l10n,
    CollectionReferenceEntry entry,
  ) {
    final bool discarded = entry.taskState == JournalTaskState.discarded;
    final TextStyle? contentStyle = Theme.of(context).textTheme.bodyLarge;
    final TextStyle? markerStyle = Theme.of(context).textTheme.titleMedium;
    final Widget row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EntrySignifierMarks(entryId: entry.id),
        SizedBox(
          width: 28,
          child: Text(
            _entrySymbol(entry.type, entry.taskState),
            textAlign: TextAlign.center,
            style: discarded
                ? markerStyle?.copyWith(decoration: TextDecoration.lineThrough)
                : markerStyle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            label: journalEntrySemanticLabel(
              l10n,
              type: entry.type,
              taskState: entry.taskState,
              content: entry.content,
            ),
            child: ExcludeSemantics(
              child: Text(
                entry.content,
                style: discarded
                    ? contentStyle?.copyWith(
                        decoration: TextDecoration.lineThrough,
                      )
                    : contentStyle,
              ),
            ),
          ),
        ),
      ],
    );
    return SizedBox(
      width: double.infinity,
      child: PopupMenuButton<_CollectionReferenceAction>(
        enabled: !_saving,
        tooltip: l10n.referenceActions,
        padding: EdgeInsets.zero,
        onSelected: (_) => unawaited(_removeReference(entry)),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _CollectionReferenceAction.remove,
            child: Text(l10n.removeCollectionReference),
          ),
        ],
        child: row,
      ),
    );
  }

  Widget _buildEntry(AppLocalizations l10n, CollectionEntry entry) {
    final TextStyle? style = Theme.of(context).textTheme.bodyLarge;
    final bool discarded = entry.taskState == JournalTaskState.discarded;
    final bool actionInProgress = _taskActionEntryId == entry.id;
    final Widget marker = actionInProgress
        ? const Center(
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : Text(
            _entrySymbol(entry.type, entry.taskState),
            style: discarded
                ? Theme.of(context).textTheme.titleMedium
                      ?.copyWith(decoration: TextDecoration.lineThrough)
                : Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          );
    final Widget row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EntrySignifierMarks(entryId: entry.id),
        SizedBox(width: 28, child: marker),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            label: journalEntrySemanticLabel(
              l10n,
              type: entry.type,
              taskState: entry.taskState,
              content: entry.content,
            ),
            child: ExcludeSemantics(
              child: Text(
                entry.content,
                style: discarded
                    ? style?.copyWith(decoration: TextDecoration.lineThrough)
                    : style,
              ),
            ),
          ),
        ),
      ],
    );
    final bool openTask =
        entry.type == JournalEntryType.task &&
        entry.taskState == JournalTaskState.open;
    if (actionInProgress) return row;

    return SizedBox(
      width: double.infinity,
      child: PopupMenuButton<_CollectionTaskAction>(
        enabled: _taskActionEntryId == null,
        tooltip: l10n.taskActions,
        padding: EdgeInsets.zero,
        onSelected: (action) {
          unawaited(_applyTaskAction(entry, action));
        },
        itemBuilder: (context) => [
          if (openTask)
            PopupMenuItem(
              value: _CollectionTaskAction.complete,
              child: Text(l10n.completeTask),
            ),
          PopupMenuItem(
            value: _CollectionTaskAction.signifiers,
            child: Text(l10n.signifiers),
          ),
          if (openTask)
            PopupMenuItem(
              value: _CollectionTaskAction.discard,
              child: Text(l10n.discardTask),
            ),
        ],
        child: row,
      ),
    );
  }

  KeyEventResult _handleEntryComposerKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isControlPressed) {
      unawaited(_capture());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _restoreActiveFocus() {
    if (defaultTargetPlatform != TargetPlatform.linux || _saving) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _saving) {
        return;
      }
      if (_selectedCollectionId == null) {
        _titleFocusNode.requestFocus();
      } else {
        _entryFocusNode.requestFocus();
      }
    });
  }

  CollectionsJournalDataSource _dataSource() {
    return ref.read(collectionsJournalDataSourceProvider);
  }

  void _open(String collectionId) {
    ref.read(daymarkNoticeProvider.notifier).dismiss();
    setState(() {
      _selectedCollectionId = collectionId;
      _collectionFuture = _dataSource().load(collectionId);
    });
    _restoreActiveFocus();
  }

  void _backToList() {
    if (widget.initialCollectionId != null) {
      context.go('/collections');
      return;
    }
    setState(() {
      _selectedCollectionId = null;
      _collectionFuture = null;
      _collectionsFuture = _dataSource().list();
    });
    _restoreActiveFocus();
  }

  Future<void> _createCollection() async {
    final String title = _titleController.text.trim();
    if (title.isEmpty || _saving) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      final String collectionId = await _dataSource().create(title: title);
      if (!mounted) return;
      _titleController.clear();
      setState(() {
        _collectionsFuture = _dataSource().list();
        _saving = false;
      });
      _showCollectionCreationUndo(collectionId);
      _restoreActiveFocus();
    } catch (error, stackTrace) {
      _reportUnexpectedCollectionsError('create', error, stackTrace);
      if (!mounted) return;
      ref
          .read(daymarkNoticeProvider.notifier)
          .showError(l10n.createCollectionFailed);
      setState(() => _saving = false);
    }
  }

  void _showCollectionCreationUndo(String collectionId) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    ref
        .read(daymarkNoticeProvider.notifier)
        .showUndo(
          message: l10n.collectionCreated,
          actionLabel: l10n.undo,
          onUndo: () => _undoCollectionCreation(collectionId),
        );
  }

  Future<void> _undoCollectionCreation(String collectionId) async {
    JournalActivityGuard.recordActivity(context);
    try {
      await _dataSource().undoCreate(collectionId);
      if (!mounted) return;
      setState(() {
        _collectionsFuture = _dataSource().list();
      });
      _restoreActiveFocus();
    } catch (error, stackTrace) {
      _reportUnexpectedCollectionsError(
        'Collection creation undo',
        error,
        stackTrace,
      );
      if (!mounted) return;
      ref
          .read(daymarkNoticeProvider.notifier)
          .showError(AppLocalizations.of(context).undoCollectionCreationFailed);
    }
  }

  Future<void> _capture() async {
    final RapidLogInput rapidLog = parseRapidLogInput(
      _entryController.text,
      fallbackType: _entryType,
    );
    final String? collectionId = _selectedCollectionId;
    if (rapidLog.content.isEmpty || collectionId == null || _saving) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      final CollectionSnapshot beforeSnapshot = await _collectionFuture!;
      final Set<String> beforeEntryIds = <String>{
        for (final CollectionEntry entry in beforeSnapshot.entries) entry.id,
      };
      await _dataSource().capture(
        collectionId: collectionId,
        type: rapidLog.type,
        content: rapidLog.content,
      );
      final CollectionSnapshot updatedSnapshot = await _dataSource().load(
        collectionId,
      );
      final List<String> capturedEntryIds = <String>[
        for (final CollectionEntry entry in updatedSnapshot.entries)
          if (!beforeEntryIds.contains(entry.id)) entry.id,
      ];
      if (!mounted) return;
      _entryController.clear();
      setState(() {
        _collectionFuture = Future<CollectionSnapshot>.value(updatedSnapshot);
        _saving = false;
      });
      if (capturedEntryIds.length == 1) {
        _showCaptureUndo(capturedEntryIds.single);
      }
      _restoreActiveFocus();
    } catch (error, stackTrace) {
      _reportUnexpectedCollectionsError('capture', error, stackTrace);
      if (!mounted) return;
      ref.read(daymarkNoticeProvider.notifier).showError(l10n.saveEntryFailed);
      setState(() => _saving = false);
    }
  }

  void _showCaptureUndo(String entryId) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    ref
        .read(daymarkNoticeProvider.notifier)
        .showUndo(
          message: l10n.entryCreated,
          actionLabel: l10n.undo,
          onUndo: () => _undoCapture(entryId),
        );
  }

  Future<void> _undoCapture(String entryId) async {
    JournalActivityGuard.recordActivity(context);
    try {
      await ref
          .read(entryCaptureUndoDataSourceProvider)
          .undoCapture(entryId: entryId);
      if (!mounted) return;
      final String? collectionId = _selectedCollectionId;
      if (collectionId != null) {
        setState(() {
          _collectionFuture = _dataSource().load(collectionId);
        });
      }
      _restoreActiveFocus();
    } catch (error, stackTrace) {
      _reportUnexpectedCollectionsError('capture undo', error, stackTrace);
      if (!mounted) return;
      ref
          .read(daymarkNoticeProvider.notifier)
          .showError(AppLocalizations.of(context).undoCaptureFailed);
    }
  }

  Future<void> _applyTaskAction(
    CollectionEntry entry,
    _CollectionTaskAction action,
  ) async {
    final String? collectionId = _selectedCollectionId;
    if (collectionId == null || _taskActionEntryId != null) return;
    if (action == _CollectionTaskAction.signifiers) {
      try {
        await showEntrySignifierDialog(
          context: context,
          ref: ref,
          entryId: entry.id,
        );
      } catch (error, stackTrace) {
        _reportUnexpectedCollectionsError('signifiers', error, stackTrace);
        if (mounted) {
          ref
              .read(daymarkNoticeProvider.notifier)
              .showError(AppLocalizations.of(context).signifierUpdateFailed);
        }
      }
      return;
    }
    final bool openTask =
        entry.type == JournalEntryType.task &&
        entry.taskState == JournalTaskState.open;
    if (!openTask) {
      return;
    }
    // Any deliberate journal action supersedes the short-lived capture Undo.
    ref.read(daymarkNoticeProvider.notifier).dismiss();
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _taskActionEntryId = entry.id);
    try {
      switch (action) {
        case _CollectionTaskAction.complete:
          await _dataSource().completeTask(entryId: entry.id);
        case _CollectionTaskAction.discard:
          await _dataSource().discardTask(entryId: entry.id);
        case _CollectionTaskAction.signifiers:
          break;
      }
      if (!mounted) return;
      setState(() {
        _collectionFuture = _dataSource().load(collectionId);
        _taskActionEntryId = null;
      });
    } catch (error, stackTrace) {
      _reportUnexpectedCollectionsError('task action', error, stackTrace);
      if (!mounted) return;
      ref.read(daymarkNoticeProvider.notifier).showError(l10n.taskActionFailed);
      setState(() => _taskActionEntryId = null);
    }
  }

  Future<void> _removeReference(CollectionReferenceEntry entry) async {
    final String? collectionId = _selectedCollectionId;
    if (collectionId == null || _saving) {
      return;
    }

    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await _dataSource().removeReference(
        collectionId: collectionId,
        entryId: entry.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _collectionFuture = _dataSource().load(collectionId);
        _saving = false;
      });
    } catch (error, stackTrace) {
      _reportUnexpectedCollectionsError('reference removal', error, stackTrace);
      if (!mounted) {
        return;
      }
      ref
          .read(daymarkNoticeProvider.notifier)
          .showError(l10n.removeCollectionReferenceFailed);
      setState(() => _saving = false);
    }
  }

  Future<void> _lock() async {
    try {
      await ref.read(journalSessionControllerProvider.notifier).lock();
    } catch (error, stackTrace) {
      _reportUnexpectedCollectionsError('lock', error, stackTrace);
    }
  }
}

enum _CollectionTaskAction { complete, signifiers, discard }

enum _CollectionReferenceAction { remove }

String _entrySymbol(JournalEntryType type, JournalTaskState? taskState) =>
    switch (type) {
      JournalEntryType.task => switch (taskState) {
        JournalTaskState.completed => '×',
        JournalTaskState.migrated => '>',
        JournalTaskState.scheduled => '<',
        JournalTaskState.discarded => '•',
        JournalTaskState.open => '•',
        null => '•',
      },
      JournalEntryType.event => '○',
      JournalEntryType.note => '–',
    };

void _reportUnexpectedCollectionsError(
  String operation,
  Object error,
  StackTrace stackTrace,
) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: FlutterError(
        'Collections $operation failed (${error.runtimeType}).',
      ),
      stack: stackTrace,
      library: 'daymark',
    ),
  );
}
