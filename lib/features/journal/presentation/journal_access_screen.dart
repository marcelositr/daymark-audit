import 'dart:io';

import 'package:daymark/core/backup/backup_file_gateway.dart';
import 'package:daymark/core/crypto/security_exception.dart';
import 'package:daymark/core/session/journal_session.dart';
import 'package:daymark/core/session/journal_session_controller.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backup_file_gateway_provider.dart';

class JournalAccessScreen extends ConsumerStatefulWidget {
  const JournalAccessScreen({super.key});

  @override
  ConsumerState<JournalAccessScreen> createState() =>
      _JournalAccessScreenState();
}

class _JournalAccessScreenState extends ConsumerState<JournalAccessScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmationController = TextEditingController();

  String? _errorMessage;
  bool _passwordVisible = false;
  bool _confirmationVisible = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<JournalAccessState> access = ref.watch(
      journalSessionControllerProvider,
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: access.when(
                data: (state) => switch (state) {
                  JournalNeedsCreation() => _buildCreate(context, l10n),
                  JournalLocked() => _buildUnlock(context, l10n),
                  JournalStorageProblem() => _buildStorageProblem(
                    context,
                    l10n,
                  ),
                  JournalUnlocked() => const Center(
                    child: CircularProgressIndicator(),
                  ),
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => _buildLoadFailure(context, l10n),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreate(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.createJournalTitle,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(l10n.createJournalMessage),
        const SizedBox(height: 28),
        _passwordField(
          controller: _passwordController,
          label: l10n.masterPassword,
          newPassword: true,
          visible: _passwordVisible,
          onToggleVisibility: () {
            setState(() => _passwordVisible = !_passwordVisible);
          },
        ),
        const SizedBox(height: 12),
        _passwordField(
          controller: _confirmationController,
          label: l10n.confirmMasterPassword,
          newPassword: true,
          visible: _confirmationVisible,
          onToggleVisibility: () {
            setState(() => _confirmationVisible = !_confirmationVisible);
          },
          onSubmitted: (_) => _createJournal(),
        ),
        _buildError(context),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _createJournal,
          child: Text(l10n.createJournal),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _restoreBackup(replacingExistingJournal: false),
          icon: const Icon(Icons.restore),
          label: Text(l10n.restoreBackup),
        ),
      ],
    );
  }

  Widget _buildUnlock(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.unlockJournalTitle,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(l10n.unlockJournalMessage),
        const SizedBox(height: 28),
        _passwordField(
          controller: _passwordController,
          label: l10n.masterPassword,
          visible: _passwordVisible,
          onToggleVisibility: () {
            setState(() => _passwordVisible = !_passwordVisible);
          },
          onSubmitted: (_) => _unlockJournal(),
        ),
        _buildError(context),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _unlockJournal,
          child: Text(l10n.unlockJournal),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _restoreBackup(replacingExistingJournal: true),
          icon: const Icon(Icons.restore),
          label: Text(l10n.restoreBackup),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    final String? errorMessage = _errorMessage;
    if (errorMessage == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        errorMessage,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  Widget _buildStorageProblem(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.journalStorageProblemTitle,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(l10n.journalStorageProblem),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => ref.invalidate(journalSessionControllerProvider),
          child: Text(l10n.tryAgain),
        ),
      ],
    );
  }

  Widget _buildLoadFailure(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.journalAccessFailed,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => ref.invalidate(journalSessionControllerProvider),
          child: Text(l10n.tryAgain),
        ),
      ],
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool visible,
    required VoidCallback onToggleVisibility,
    bool newPassword = false,
    ValueChanged<String>? onSubmitted,
  }) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return TextField(
      controller: controller,
      obscureText: !visible,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: <String>[
        newPassword ? AutofillHints.newPassword : AutofillHints.password,
      ],
      textInputAction: onSubmitted == null
          ? TextInputAction.next
          : TextInputAction.done,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          onPressed: onToggleVisibility,
          tooltip: visible ? l10n.hidePassword : l10n.showPassword,
          icon: Icon(
            visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          ),
        ),
      ),
    );
  }

  Future<void> _createJournal() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String password = _passwordController.text;

    if (password.isEmpty) {
      setState(() => _errorMessage = l10n.masterPasswordRequired);
      return;
    }
    if (password != _confirmationController.text) {
      setState(() => _errorMessage = l10n.passwordsDoNotMatch);
      return;
    }

    setState(() => _errorMessage = null);
    try {
      await ref
          .read(journalSessionControllerProvider.notifier)
          .create(masterPassword: password);
    } catch (error, stackTrace) {
      _reportUnexpectedAccessError(error, stackTrace);
      if (mounted) {
        setState(() => _errorMessage = l10n.journalAccessFailed);
      }
    }
  }

  Future<void> _unlockJournal() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String password = _passwordController.text;

    if (password.isEmpty) {
      setState(() => _errorMessage = l10n.masterPasswordRequired);
      return;
    }

    setState(() => _errorMessage = null);
    try {
      await ref
          .read(journalSessionControllerProvider.notifier)
          .unlock(masterPassword: password);
    } on JournalUnlockException {
      if (mounted) {
        setState(() => _errorMessage = l10n.journalAccessFailed);
      }
    } catch (error, stackTrace) {
      _reportUnexpectedAccessError(error, stackTrace);
      if (mounted) {
        setState(() => _errorMessage = l10n.journalAccessFailed);
      }
    }
  }

  Future<void> _restoreBackup({required bool replacingExistingJournal}) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _errorMessage = null);

    final File? backupFile;
    try {
      backupFile = await ref
          .read(backupFileGatewayProvider)
          .pickBackup(dialogTitle: l10n.restoreBackupTitle);
    } on BackupFileSelectionException {
      if (mounted) {
        setState(() => _errorMessage = l10n.backupFileSelectionFailed);
      }
      return;
    } catch (error, stackTrace) {
      _reportUnexpectedAccessError(error, stackTrace);
      if (mounted) {
        setState(() => _errorMessage = l10n.backupFileSelectionFailed);
      }
      return;
    }
    if (backupFile == null || !mounted) {
      return;
    }

    final String? password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _RestorePasswordDialog(
        l10n: l10n,
        replacingExistingJournal: replacingExistingJournal,
      ),
    );
    if (password == null || !mounted) {
      return;
    }

    try {
      await ref
          .read(journalSessionControllerProvider.notifier)
          .restoreBackup(backupFile: backupFile, masterPassword: password);
    } on BackupAuthenticationException {
      if (mounted) {
        setState(() => _errorMessage = l10n.restoreBackupAuthenticationFailed);
      }
    } on BackupFormatException {
      if (mounted) {
        setState(() => _errorMessage = l10n.restoreBackupInvalid);
      }
    } on BackupCompatibilityException {
      if (mounted) {
        setState(() => _errorMessage = l10n.restoreBackupIncompatible);
      }
    } on BackupRestoreException {
      if (mounted) {
        setState(() => _errorMessage = l10n.restoreBackupFailed);
      }
    } catch (error, stackTrace) {
      _reportUnexpectedAccessError(error, stackTrace);
      if (mounted) {
        setState(() => _errorMessage = l10n.restoreBackupFailed);
      }
    }
  }
}

final class _RestorePasswordDialog extends StatefulWidget {
  const _RestorePasswordDialog({
    required this.l10n,
    required this.replacingExistingJournal,
  });

  final AppLocalizations l10n;
  final bool replacingExistingJournal;

  @override
  State<_RestorePasswordDialog> createState() => _RestorePasswordDialogState();
}

final class _RestorePasswordDialogState extends State<_RestorePasswordDialog> {
  final TextEditingController _passwordController = TextEditingController();
  String? _errorMessage;
  bool _passwordVisible = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = widget.l10n;
    return AlertDialog(
      title: Text(l10n.restoreBackupTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.replacingExistingJournal
                  ? l10n.restoreBackupExistingMessage
                  : l10n.restoreBackupEmptyMessage,
            ),
            const SizedBox(height: 12),
            Text(l10n.restoreBackupPasswordMessage),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              obscureText: !_passwordVisible,
              autocorrect: false,
              enableSuggestions: false,
              autofocus: true,
              autofillHints: const <String>[AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l10n.masterPassword,
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() => _passwordVisible = !_passwordVisible);
                  },
                  tooltip: _passwordVisible
                      ? l10n.hidePassword
                      : l10n.showPassword,
                  icon: Icon(
                    _passwordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.restoreBackupConfirm),
        ),
      ],
    );
  }

  void _submit() {
    final String password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorMessage = widget.l10n.masterPasswordRequired);
      return;
    }
    Navigator.of(context).pop(password);
  }
}

void _reportUnexpectedAccessError(Object error, StackTrace stackTrace) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: FlutterError(
        'Journal access operation failed (${error.runtimeType}).',
      ),
      stack: stackTrace,
      library: 'daymark',
    ),
  );
}
