import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update_service.dart';
import '../router/app_router.dart';

/// Checks once per Android app session, after the first frame is visible.
class AppUpdatePrompt extends StatefulWidget {
  const AppUpdatePrompt({super.key, required this.child});

  final Widget child;

  @override
  State<AppUpdatePrompt> createState() => _AppUpdatePromptState();
}

class _AppUpdatePromptState extends State<AppUpdatePrompt> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (_checked || defaultTargetPlatform != TargetPlatform.android) return;
    _checked = true;

    final update = await AppUpdateService().checkForUpdate();
    if (!mounted || update == null) return;
    // MaterialApp.builder wraps the router, so its own BuildContext is above
    // the Navigator. Use the router navigator's context to make the dialog
    // work from every launch route (splash, sign-in, or chat).
    final navigatorContext = rootNavigatorKey.currentContext;
    if (navigatorContext == null || !navigatorContext.mounted) return;
    await showDialog<void>(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (context) => _UpdateDialog(update: update),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.update});

  final AppUpdateInfo update;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _openingDownload = false;

  Future<void> _openDownload() async {
    setState(() => _openingDownload = true);
    final opened = await launchUrl(
      widget.update.downloadUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    setState(() => _openingDownload = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the update download.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.system_update_rounded,
                  color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 18),
            Text(
              'Update available',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'A newer version of OurChat is ready to install.',
              style: theme.textTheme.bodyMedium,
            ),
            if (widget.update.releaseNotes case final notes?) ...[
              const SizedBox(height: 14),
              Text(notes, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                TextButton(
                  onPressed: _openingDownload
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Later'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _openingDownload ? null : _openDownload,
                  child: _openingDownload
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Update now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
