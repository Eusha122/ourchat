import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../posts/data/post_models.dart';
import '../data/conversations_api.dart';
import '../state/chat_providers.dart';
import 'conversation_screen.dart';

class ConversationEntryScreen extends ConsumerStatefulWidget {
  const ConversationEntryScreen({
    super.key,
    required this.conversationId,
    this.initialOtherParticipant,
  });

  final String conversationId;
  final PostAuthor? initialOtherParticipant;

  @override
  ConsumerState<ConversationEntryScreen> createState() =>
      _ConversationEntryScreenState();
}

class _ConversationEntryScreenState
    extends ConsumerState<ConversationEntryScreen> {
  PostAuthor? _loadedOtherParticipant;
  bool _isLoading = false;
  String? _error;

  PostAuthor? get _otherParticipant =>
      widget.initialOtherParticipant ?? _loadedOtherParticipant;

  @override
  void initState() {
    super.initState();
    if (widget.initialOtherParticipant == null) {
      _loadConversation();
    }
  }

  @override
  void didUpdateWidget(covariant ConversationEntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final routeChanged = oldWidget.conversationId != widget.conversationId;
    final initialChanged =
        oldWidget.initialOtherParticipant != widget.initialOtherParticipant;
    if (!routeChanged && !initialChanged) return;

    _loadedOtherParticipant = null;
    _error = null;
    if (widget.initialOtherParticipant == null) {
      _loadConversation();
    }
  }

  Future<void> _loadConversation() async {
    final conversationId = widget.conversationId;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final conversation = await ref
          .read(conversationsApiProvider)
          .fetchConversation(conversationId);
      if (!mounted || widget.conversationId != conversationId) return;
      setState(() => _loadedOtherParticipant = conversation.otherParticipant);
    } on ConversationsApiException catch (e) {
      if (!mounted || widget.conversationId != conversationId) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted && widget.conversationId == conversationId) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final otherParticipant = _otherParticipant;
    if (otherParticipant != null) {
      return ConversationScreen(
        key: ValueKey('${widget.conversationId}:${otherParticipant.id}'),
        conversationId: widget.conversationId,
        otherParticipant: otherParticipant,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF5B4CF5),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Container(
              width: 360,
              padding: const EdgeInsets.fromLTRB(28, 30, 28, 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(34),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1F185D).withValues(alpha: 0.18),
                    blurRadius: 40,
                    offset: const Offset(0, 18),
                  ),
                  BoxShadow(
                    color: const Color(0xFF1F185D).withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeInOutCubic,
                switchOutCurve: Curves.easeInOutCubic,
                child: _error == null
                    ? const _LoadingConversation(key: ValueKey('loading'))
                    : _ConversationLoadError(
                        key: const ValueKey('error'),
                        message: _error!,
                        isRetrying: _isLoading,
                        onRetry: _loadConversation,
                        onBack: () => context.go('/chats'),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingConversation extends StatelessWidget {
  const _LoadingConversation({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: Color(0xFF5D4EF5),
          ),
        ),
        SizedBox(height: 18),
        Text(
          'Opening chat...',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Color(0xFF1B1B1B),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ConversationLoadError extends StatelessWidget {
  const _ConversationLoadError({
    super.key,
    required this.message,
    required this.isRetrying,
    required this.onRetry,
    required this.onBack,
  });

  final String message;
  final bool isRetrying;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.lock_outline_rounded,
          color: Color(0xFF5D4EF5),
          size: 32,
        ),
        const SizedBox(height: 16),
        const Text(
          'Could not open this chat',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Color(0xFF1B1B1B),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Color(0xFF8A8A8A),
            fontSize: 12,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _RouteRecoveryButton(
                label: 'Chats',
                onTap: onBack,
                background: const Color(0xFFF2F1FF),
                foreground: const Color(0xFF5D4EF5),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RouteRecoveryButton(
                label: isRetrying ? 'Retrying' : 'Retry',
                onTap: isRetrying ? null : onRetry,
                background: const Color(0xFF5D4EF5),
                foreground: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RouteRecoveryButton extends StatelessWidget {
  const _RouteRecoveryButton({
    required this.label,
    required this.onTap,
    required this.background,
    required this.foreground,
  });

  final String label;
  final VoidCallback? onTap;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOutCubic,
        opacity: onTap == null ? 0.55 : 1,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: foreground,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
