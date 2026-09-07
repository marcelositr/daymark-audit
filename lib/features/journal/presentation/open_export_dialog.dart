import 'dart:convert';

import 'package:daymark/core/crypto/security_exception.dart';
import 'package:daymark/core/export/export_file_gateway.dart';
import 'package:daymark/core/export/open_export_service.dart';
import 'package:daymark/core/session/journal_session_controller.dart';
import 'package:daymark/l10n/app_localizations.dart';
import 'package:daymark/presentation/daymark_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'export_file_gateway_provider.dart';

enum OpenExportOutcome { saved, copied }

enum _OpenExportAction { copy, save }

Future<void> showOpenExportDialog(BuildContext context) async {
  final OpenExportOutcome? outcome = await showDialog<OpenExportOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const OpenExportDialog(),
  );

  if (outcome == null || !context.mounted) {
    return;
  }

  final AppLocalizations l10n = AppLocalizations.of(context);
  final String message = switch (outcome) {
    OpenExportOutcome.saved => l10n.openExportSaved,
    OpenExportOutcome.copied => l10n.openExportCopied,
  };
  daymarkNoticeControllerOf(context).showInfo(message);
}

final class OpenExportDialog extends ConsumerStatefulWidget {
  const OpenExportDialog({super.key});

  @override
  ConsumerState<OpenExportDialog> createState() => _OpenExportDialogState();
}

final class _OpenExportDialogState extends ConsumerState<OpenExportDialog> {
  final TextEditingController _passwordController = TextEditingController();

  OpenExportFormat _format = OpenExportFormat.markdown;
  _OpenExportAction? _busyAction;
  bool _passwordVisible = false;
  String? _errorMessage;

  bool get _busy => _busyAction != null;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.openExportTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.openExportMessage),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              enabled: !_busy,
              autofocus: true,
              obscureText: !_passwordVisible,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const <String>[AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: _busy
                  ? null
                  : (_) => _perform(_OpenExportAction.save),
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
            const SizedBox(height: 16),
            SegmentedButton<OpenExportFormat>(
              showSelectedIcon: false,
              segments: <ButtonSegment<OpenExportFormat>>[
                ButtonSegment<OpenExportFormat>(
                  value: OpenExportFormat.markdown,
                  label: Text(l10n.openExportFormatMarkdown),
                ),
                ButtonSegment<OpenExportFormat>(
                  value: OpenExportFormat.json,
                  label: Text(l10n.openExportFormatJson),
                ),
              ],
              selected: <OpenExportFormat>{_format},
              onSelectionChanged: _busy
                  ? null
                  : (selection) {
                      setState(() => _format = selection.single);
                    },
            ),
            const SizedBox(height: 16),
            Text(
              l10n.openExportWarning,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _perform(_OpenExportAction.copy),
          child: _busyAction == _OpenExportAction.copy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.openExportCopy),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _perform(_OpenExportAction.save),
          child: _busyAction == _OpenExportAction.save
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.openExportSave),
        ),
      ],
    );
  }

  Future<void> _perform(_OpenExportAction action) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorMessage = l10n.masterPasswordRequired);
      return;
    }

    setState(() {
      _busyAction = action;
      _errorMessage = null;
    });

    Uint8List? bytes;
    try {
      final JournalSessionController controller = ref.read(
        journalSessionControllerProvider.notifier,
      );

      // Reauthenticate before creating any plaintext representation.
      await controller.reauthenticate(masterPassword: password);

      final OpenExportDocument document = await controller.createOpenExport(
        format: _format,
      );

      if (action == _OpenExportAction.copy) {
        await Clipboard.setData(ClipboardData(text: document.contents));
        if (mounted) {
          Navigator.of(context).pop(OpenExportOutcome.copied);
        }
        return;
      }

      bytes = Uint8List.fromList(utf8.encode(document.contents));
      final bool saved = await ref
          .read(exportFileGatewayProvider)
          .saveExport(
            bytes: bytes,
            suggestedName: _exportFileName(DateTime.now(), _format),
            dialogTitle: l10n.openExportTitle,
          );

      if (!saved) {
        if (mounted) {
          setState(() => _busyAction = null);
        }
        return;
      }

      if (mounted) {
        Navigator.of(context).pop(OpenExportOutcome.saved);
      }
    } on JournalUnlockException {
      _setError(l10n.openExportAuthenticationFailed);
    } on ExportFileSelectionException {
      _setError(l10n.openExportFileSelectionFailed);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: FlutterError(
            'Open export operation failed (${error.runtimeType}).',
          ),
          stack: stackTrace,
          library: 'daymark',
        ),
      );
      _setError(
        action == _OpenExportAction.copy
            ? l10n.openExportCopyFailed
            : l10n.openExportFailed,
      );
    } finally {
      final Uint8List? buffer = bytes;
      if (buffer != null) {
        buffer.fillRange(0, buffer.length, 0);
      }
    }
  }

  void _setError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _busyAction = null;
      _errorMessage = message;
    });
  }
}

String _exportFileName(DateTime dateTime, OpenExportFormat format) {
  final DateTime utc = dateTime.toUtc();
  String twoDigits(int value) => value.toString().padLeft(2, '0');

  return 'daymark-open-export-'
      '${utc.year.toString().padLeft(4, '0')}'
      '${twoDigits(utc.month)}'
      '${twoDigits(utc.day)}T'
      '${twoDigits(utc.hour)}'
      '${twoDigits(utc.minute)}'
      '${twoDigits(utc.second)}Z.'
      '${format.extension}';
}
