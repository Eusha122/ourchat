import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/state/auth_controller.dart';
import '../features/chat/data/chat_models.dart';
import '../features/chat/state/chat_providers.dart';
import 'notification_service.dart';

/// Lives for the whole app session (mounted via [MaterialApp.builder], so it
/// survives navigation) and pops an in-app banner whenever a message arrives
/// for a conversation that isn't the one currently on screen. The sound
/// itself is triggered inside SocketService — this widget only owns the
/// visual banner.
class GlobalMessageListener extends ConsumerStatefulWidget {
  const GlobalMessageListener({
    super.key,
    required this.scaffoldMessengerKey,
    required this.child,
  });

  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;
  final Widget child;

  @override
  ConsumerState<GlobalMessageListener> createState() =>
      _GlobalMessageListenerState();
}

class _GlobalMessageListenerState extends ConsumerState<GlobalMessageListener> {
  StreamSubscription<ChatMessage>? _sub;

  @override
  void initState() {
    super.initState();
    ref.listenManual(socketServiceProvider, (previous, next) {
      _sub?.cancel();
      _sub = next?.onMessage.listen(_onMessage);
    }, fireImmediately: true);
  }

  void _onMessage(ChatMessage message) {
    final myId = ref.read(authControllerProvider).value?.user?.id;
    if (message.sender.id == myId) return; // our own echoed message

    final sender = message.sender;
    final name = sender.displayName?.isNotEmpty == true
        ? sender.displayName!
        : '@${sender.username}';
    final preview = message.isUnsent
        ? 'Unsent a message'
        : message.text?.isNotEmpty == true
        ? message.text!
        : switch (message.type) {
            MessageType.image => 'Sent a photo',
            MessageType.file => 'Sent a file',
            MessageType.call =>
              message.callKind == 'VIDEO'
                  ? 'Incoming video call'
                  : 'Incoming voice call',
            MessageType.link => 'Sent a link',
            MessageType.text => 'Sent a message',
          };

    // Always create the OS notification. In particular, this covers the
    // common test case where the same conversation is open on the phone.
    // The in-app banner remains suppressed there because the message is
    // already visible in the thread.
    NotificationService().showMessageNotification(title: name, body: preview);
    if (ref.read(activeConversationIdProvider) == message.conversationId) {
      return; // already looking at this chat
    }

    widget.scaffoldMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1B1B1B),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Color(0xFFD8D8D8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Open',
            textColor: const Color(0xFF9E93FF),
            onPressed: () {
              final rootContext = widget.scaffoldMessengerKey.currentContext;
              if (rootContext != null) {
                GoRouter.of(
                  rootContext,
                ).push('/chats/${message.conversationId}', extra: sender);
              }
            },
          ),
        ),
      );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
