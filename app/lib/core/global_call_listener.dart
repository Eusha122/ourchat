import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/calls/call_session_screen.dart';
import '../features/calls/call_models.dart';
import '../features/chat/state/chat_providers.dart';
import '../router/app_router.dart';
import 'call_ringtone_service.dart';
import 'notification_service.dart';

/// Receives offers no matter which tab is open and presents a native incoming
/// call screen. The socket itself remains connected for the whole signed-in
/// session, so a call is never dependent on visiting the chat tab first.
class GlobalCallListener extends ConsumerStatefulWidget {
  const GlobalCallListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<GlobalCallListener> createState() => _GlobalCallListenerState();
}

class _GlobalCallListenerState extends ConsumerState<GlobalCallListener> {
  StreamSubscription<CallOffer>? _offerSub;
  bool _showingCall = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(socketServiceProvider, (previous, next) {
      _offerSub?.cancel();
      _offerSub = next?.onCallOffer.listen(_showIncomingCall);
    }, fireImmediately: true);
  }

  Future<void> _showIncomingCall(CallOffer offer) async {
    if (_showingCall) return;
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    _showingCall = true;
    final name = offer.caller.displayName?.isNotEmpty == true
        ? offer.caller.displayName!
        : '@${offer.caller.username}';
    NotificationService().showIncomingCallNotification(
      callId: offer.callId,
      caller: name,
      isVideo: offer.kind == CallKind.video,
    );
    CallRingtoneService.instance.playIncoming();
    try {
      await navigator.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => CallSessionScreen.incoming(offer: offer),
        ),
      );
    } finally {
      CallRingtoneService.instance.stop();
      NotificationService().dismissIncomingCall(offer.callId);
      _showingCall = false;
    }
  }

  @override
  void dispose() {
    _offerSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
