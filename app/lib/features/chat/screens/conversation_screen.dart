import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';
import '../../posts/data/post_models.dart';
import '../data/chat_models.dart';
import '../data/conversations_api.dart';
import '../state/chat_providers.dart';
import '../widgets/link_message_card.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversationId,
    required this.otherParticipant,
  });

  final String conversationId;
  final PostAuthor otherParticipant;

  @override
  ConsumerState<ConversationScreen> createState() =>
      _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  StreamSubscription<ChatMessage>? _messageSub;
  StreamSubscription<TypingEvent>? _typingSub;
  Timer? _typingResetTimer;
  bool _isLoading = true;
  bool _isSending = false;
  bool _otherIsTyping = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    ref.read(socketServiceProvider)?.joinConversation(widget.conversationId);
    _messageSub = ref
        .read(socketServiceProvider)
        ?.onMessage
        .where((m) => m.conversationId == widget.conversationId)
        .listen(_onIncomingMessage);
    _typingSub = ref
        .read(socketServiceProvider)
        ?.onTyping
        .where((t) => t.userId == widget.otherParticipant.id)
        .listen(_onTyping);
    ref.read(conversationsApiProvider).markRead(widget.conversationId);
  }

  @override
  void dispose() {
    ref.read(socketServiceProvider)?.leaveConversation(widget.conversationId);
    _messageSub?.cancel();
    _typingSub?.cancel();
    _typingResetTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onIncomingMessage(ChatMessage message) {
    if (!mounted) return;
    final myId = ref.read(authControllerProvider).value?.user?.id;
    if (message.sender.id == myId) return; // avoid duplicating our own send
    setState(() => _messages.insert(0, message));
    ref.read(conversationsApiProvider).markRead(widget.conversationId);
  }

  void _onTyping(TypingEvent event) {
    if (!mounted) return;
    setState(() => _otherIsTyping = event.isTyping);
    _typingResetTimer?.cancel();
    if (event.isTyping) {
      _typingResetTimer = Timer(
        const Duration(seconds: 4),
        () => mounted ? setState(() => _otherIsTyping = false) : null,
      );
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(conversationsApiProvider)
          .fetchMessages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(page.messages);
      });
    } on ConversationsApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _textController.clear();
    ref.read(socketServiceProvider)?.sendTyping(widget.conversationId, false);
    try {
      final message = await ref
          .read(conversationsApiProvider)
          .sendMessage(widget.conversationId, text);
      if (!mounted) return;
      setState(() => _messages.insert(0, message));
    } on ConversationsApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final other = widget.otherParticipant;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          other.displayName?.isNotEmpty == true
              ? other.displayName!
              : '@${other.username}',
        ),
      ),
      body: Column(
        children: [
          if (_otherIsTyping)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  'typing...',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          Expanded(child: _buildMessages()),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      onChanged: (value) => ref
                          .read(socketServiceProvider)
                          ?.sendTyping(
                            widget.conversationId,
                            value.isNotEmpty,
                          ),
                      decoration: const InputDecoration(
                        hintText: 'Message...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isSending ? null : _send,
                    icon: _isSending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(child: Text('Say hi!'));
    }

    final myId = ref.watch(authControllerProvider).value?.user?.id;

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.all(8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMine = message.sender.id == myId;

        if (message.type == MessageType.link) {
          return Align(
            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: LinkMessageCard(message: message, isMine: isMine),
            ),
          );
        }

        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isMine
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              message.text ?? '',
              style: TextStyle(
                color: isMine
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}
