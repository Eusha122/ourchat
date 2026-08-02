import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

class _AppUpdatePromptState extends State<AppUpdatePrompt>
    with WidgetsBindingObserver {
  bool _checking = false;
  AppUpdateInfo? _requiredUpdate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A release published while the app sat in the background would
    // otherwise go unnoticed until the process was killed and cold started,
    // which on a phone can be days.
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_checking ||
        _requiredUpdate != null ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _checking = true;
    try {
      final update = await AppUpdateService().checkForUpdate();
      if (!mounted || update == null) return;
      setState(() => _requiredUpdate = update);
    } finally {
      _checking = false;
    }
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
  final _updateService = AppUpdateService();
  bool _installing = false;
  double? _downloadProgress;
  DownloadedUpdate? _downloadedUpdate;
  String? _status;

  Future<void> _downloadAndInstall() async {
    if (_installing) return;
    setState(() {
      _installing = true;
      _status = null;
      _downloadProgress = _downloadedUpdate == null ? 0 : null;
    });
    try {
      final downloaded =
          _downloadedUpdate ??
          await _updateService.downloadApk(
            widget.update,
            onProgress: (received, total) {
              if (!mounted) return;
              setState(() {
                _downloadProgress = total > 0 ? received / total : null;
              });
            },
          );
      if (!mounted) return;
      _downloadedUpdate = downloaded;
      final installerResult = await _updateService.openInstaller(
        downloaded.file,
      );
      if (!mounted) return;
      setState(() {
        _status = installerResult == ApkInstallerResult.permissionRequired
            ? 'Allow installs from OurChat in Android settings, then return and tap Install update.'
            : 'Android installer opened.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _status = 'Could not download the update. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _installing = false;
          _downloadProgress = null;
        });
      }
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
              if (_status != null) ...[
                Text(
                  _status!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    height: 1.4,
                    color: Color(0xFF6E6E78),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _installing ? null : _downloadAndInstall,
                  style: FilledButton.styleFrom(
                    backgroundColor: _purple,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _installing
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                value: _downloadProgress,
                                strokeWidth: 2,
                                valueColor: const AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _downloadProgress == null
                                  ? 'Preparing update…'
                                  : 'Downloading ${(_downloadProgress! * 100).round()}%',
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          _downloadedUpdate == null
                              ? 'Update now'
                              : 'Install update',
                          style: const TextStyle(
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
