import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update_service.dart';

const _purple = Color(0xFF5D4EF5);
const _purpleEnd = Color(0xFF6C63FF);

/// Checks once per Android app session, after the first frame is visible.
/// While a mandatory update is pending, this replaces [child] outright with
/// a full-screen gate instead of showing a dismissible dialog — a dialog
/// route can get swept away by the app's own startup navigation (splash to
/// sign-in/chats), which is why an earlier version of this flashed and
/// disappeared. Withholding the child entirely has no such route to lose.
class AppUpdatePrompt extends StatefulWidget {
  const AppUpdatePrompt({super.key, required this.child});

  final Widget child;

  @override
  State<AppUpdatePrompt> createState() => _AppUpdatePromptState();
}

class _AppUpdatePromptState extends State<AppUpdatePrompt> {
  bool _checked = false;
  AppUpdateInfo? _requiredUpdate;

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
    setState(() => _requiredUpdate = update);
  }

  @override
  Widget build(BuildContext context) {
    final update = _requiredUpdate;
    if (update == null) return widget.child;
    return _UpdateGate(update: update);
  }
}

class _UpdateGate extends StatefulWidget {
  const _UpdateGate({required this.update});

  final AppUpdateInfo update;

  @override
  State<_UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<_UpdateGate> {
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
    // No Navigator is mounted underneath while this gate is showing (the
    // router's `child` is withheld entirely), so there's nothing for the
    // system back button to pop into — it falls through to backgrounding
    // the app, same as any other Android app with nothing left to pop.
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFF),
      body: SafeArea(
        child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_purpleEnd, _purple],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: _purple.withValues(alpha: 0.32),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 26),
                const Text(
                  'Update required',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1B1B1B),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'A newer version of OurChat is available. Please '
                  'update to keep using the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13.5,
                    height: 1.5,
                    color: Color(0xFF6E6E78),
                  ),
                ),
                if (widget.update.releaseNotes case final notes?) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F3FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      notes,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        height: 1.5,
                        color: Color(0xFF4A4A55),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _openingDownload ? null : _openDownload,
                    style: FilledButton.styleFrom(
                      backgroundColor: _purple,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _openingDownload
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text(
                            'Update now',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }
}
