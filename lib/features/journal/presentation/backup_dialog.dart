import 'dart:io';

import 'package:daymark/core/backup/backup_file_gateway.dart';
import 'package:daymark/core/crypto/security_exception.dart';
import 'package:daymark/core/session/journal_session_controller.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:daymark/presentation/daymark_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'backup_file_gateway_provider.dart';

Future<void> showBackupDialog(BuildContext context) async {
  final bool? saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const BackupDialog(),
  );

  if (saved == true && context.mounted) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    daymarkNoticeControllerOf(context).showInfo(l10n.backupSaved);
  }
}

final class BackupDialog extends ConsumerStatefulWidget {
  const BackupDialog({super.key});

  @override
  ConsumerState<BackupDialog> createState() => _BackupDialogState();
}

final class _BackupDialogState extends ConsumerState<BackupDialog> {
  final TextEditingController _passwordController = TextEditingController();

  bool _busy = false;
  bool _passwordVisible = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.encryptedBackupTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.encryptedBackupMessage),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              enabled: !_busy,
              obscureText: !_passwordVisible,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const <String>[AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: _busy ? null : (_) => _createBackup(),
              decoration: InputDecoration(
                labelText: l10n.masterPassword,
                suffixIcon: IconButton(
                  onPressed: _busy
                      ? null
                      : () {
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
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _busy ? null : _createBackup,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.createBackup),
        ),
      ],
    );
  }

  Future<void> _createBackup() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorMessage = l10n.masterPasswordRequired);
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    File? temporaryBackup;
    try {
      final String backupFileName = _backupFileName(DateTime.now());
      final Directory tempDirectory = await getTemporaryDirectory();
      temporaryBackup = File(
        '${tempDirectory.path}${Platform.pathSeparator}$backupFileName.tmp',
      );

      await ref
          .read(journalSessionControllerProvider.notifier)
          .createBackup(backupFile: temporaryBackup, masterPassword: password);

      final bool saved = await ref
          .read(backupFileGatewayProvider)
          .saveBackup(
            sourceFile: temporaryBackup,
            suggestedName: backupFileName,
            dialogTitle: l10n.encryptedBackupTitle,
          );
      if (!saved) {
        if (mounted) {
          setState(() => _busy = false);
        }
        return;
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on BackupAuthenticationException {
      _setError(l10n.backupAuthenticationFailed);
    } on BackupWriteException {
      _setError(l10n.backupFailed);
    } on BackupFormatException {
      _setError(l10n.backupFailed);
    } on BackupFileSelectionException {
      _setError(l10n.backupFileSelectionFailed);
    } catch (error, stackTrace) {
      _reportBackupError(error, stackTrace);
      _setError(l10n.backupFailed);
    } finally {
      final File? file = temporaryBackup;
      if (file != null) {
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } on FileSystemException {
          // The backup container is encrypted. Cleanup is best effort and the
          // primary user-visible operation result is preserved.
        }
      }
    }
  }

  void _setError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _errorMessage = message;
    });
  }
}

String _backupFileName(DateTime dateTime) {
  final DateTime utc = dateTime.toUtc();
  String twoDigits(int value) => value.toString().padLeft(2, '0');

  return 'daymark-'
      '${utc.year.toString().padLeft(4, '0')}'
      '${twoDigits(utc.month)}'
      '${twoDigits(utc.day)}T'
      '${twoDigits(utc.hour)}'
      '${twoDigits(utc.minute)}'
      '${twoDigits(utc.second)}Z.daymark-backup';
}

void _reportBackupError(Object error, StackTrace stackTrace) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: FlutterError(
        'Encrypted backup operation failed (${error.runtimeType}).',
      ),
      stack: stackTrace,
      library: 'daymark',
    ),
  );
}
