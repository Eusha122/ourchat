import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';
import '../../posts/data/post_models.dart';
import '../data/chat_models.dart';
import '../data/conversations_api.dart';
import '../state/chat_providers.dart';
import '../widgets/link_message_card.dart';

const _ink = Color(0xFF1B1B1B);
const _muted = Color(0xFF8A8A8A);
const _purple = Color(0xFF5D4EF5);
const _purpleLight = Color(0xFF6C63FF);
const _motion = Duration(milliseconds: 250);

void _showComingSoon(BuildContext context, String feature) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$feature isn\'t available yet')));
}

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversationId,
    required this.otherParticipant,
  });

  final String conversationId;
  final PostAuthor otherParticipant;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
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
    final name = other.displayName?.isNotEmpty == true
        ? other.displayName!
        : '@${other.username}';

    return Scaffold(
      backgroundColor: _purple,
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_purpleLight, _purple],
          ),
        ),
        child: Column(
          children: [
            _ConversationHeader(
              name: name,
              avatarUrl: other.avatarUrl,
              isTyping: _otherIsTyping,
            ),
            Expanded(child: _buildMessages()),
            _Composer(
              controller: _textController,
              isSending: _isSending,
              onSend: _send,
              onTypingChanged: (value) => ref
                  .read(socketServiceProvider)
                  ?.sendTyping(widget.conversationId, value.isNotEmpty),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 8,
          height: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _TextAction(label: 'Retry', onTap: _load),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return _EmptyConversation(name: widget.otherParticipant.username);
    }

    final myId = ref.watch(authControllerProvider).value?.user?.id;

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMine = message.sender.id == myId;

        if (message.type == MessageType.link) {
          return Align(
            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: LinkMessageCard(message: message, isMine: isMine),
            ),
          );
        }

        return _Bubble(text: message.text ?? '', mine: isMine);
      },
    );
  }
}

/// White header card with softly rounded bottom corners, floating on the
/// purple conversation canvas.
class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.name,
    required this.avatarUrl,
    required this.isTyping,
  });

  final String name;
  final String? avatarUrl;
  final bool isTyping;

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: Color(0xFFECE9FF),
      child: Icon(Icons.person_rounded, color: _purple, size: 22),
    );

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F2B2468),
            blurRadius: 40,
            offset: Offset(0, 14),
          ),
          BoxShadow(
            color: Color(0x0F2B2468),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 22, 0),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const SizedBox(
                    width: 34,
                    height: 44,
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: _ink,
                      size: 21,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: ClipOval(
                    child: avatarUrl == null
                        ? placeholder
                        : CachedNetworkImage(
                            imageUrl: avatarUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => placeholder,
                          ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: _ink,
                          fontSize: 14.5,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      AnimatedSwitcher(
                        duration: _motion,
                        switchInCurve: Curves.easeInOutCubic,
                        switchOutCurve: Curves.easeInOutCubic,
                        child: Text(
                          isTyping ? 'typing...' : 'Online',
                          key: ValueKey(isTyping),
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: _muted,
                            fontSize: 10,
                            height: 1.2,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _OutlineCircleButton(
                  icon: Icons.videocam_outlined,
                  onTap: () => _showComingSoon(context, 'Video calls'),
                ),
                const SizedBox(width: 10),
                _OutlineCircleButton(
                  icon: Icons.call_outlined,
                  onTap: () => _showComingSoon(context, 'Voice calls'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineCircleButton extends StatefulWidget {
  const _OutlineCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_OutlineCircleButton> createState() => _OutlineCircleButtonState();
}

class _OutlineCircleButtonState extends State<_OutlineCircleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: _motion,
        curve: Curves.easeInOutCubic,
        child: Container(
          width: 37,
          height: 37,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: _ink, width: 1.2),
          ),
          child: Icon(widget.icon, color: _ink, size: 17),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          color: mine ? Colors.white : Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          boxShadow: mine
              ? [
                  BoxShadow(
                    color: const Color(0xFF2B2468).withValues(alpha: 0.10),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Poppins',
            color: mine ? const Color(0xFF2A2438) : Colors.white,
            fontSize: 12,
            height: 1.4,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.isSending,
    required this.onSend,
    required this.onTypingChanged,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;
  final ValueChanged<String> onTypingChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2B2468).withValues(alpha: 0.12),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: const Color(0xFF2B2468).withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 0, 10),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showComingSoon(context, 'Voice messages'),
                        child: Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF0EFFC),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.mic_rounded,
                            color: _purple,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 4,
                        cursorColor: _purple,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: _ink,
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w400,
                        ),
                        onChanged: onTypingChanged,
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: false,
                          hintText: 'Type a message',
                          hintStyle: TextStyle(
                            fontFamily: 'Poppins',
                            color: Color(0xFF9A9AA5),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.fromLTRB(10, 17, 0, 17),
                        ),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showComingSoon(context, 'Attachments'),
                      child: const SizedBox(
                        width: 44,
                        height: 52,
                        child: Icon(
                          Icons.attachment_rounded,
                          color: Color(0xFF9A9AA5),
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            _SendButton(isSending: isSending, onPressed: onSend),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatefulWidget {
  const _SendButton({required this.isSending, required this.onPressed});

  final bool isSending;
  final VoidCallback onPressed;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (!widget.isSending) widget.onPressed();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: _motion,
        curve: Curves.easeInOutCubic,
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2B2468).withValues(alpha: 0.12),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: const Color(0xFF2B2468).withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: _motion,
            child: widget.isSending
                ? const SizedBox(
                    key: ValueKey('sending'),
                    width: 8,
                    height: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _purple,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                : const Padding(
                    key: ValueKey('send'),
                    padding: EdgeInsets.only(left: 3),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: _purple,
                      size: 26,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: _purple,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.waving_hand_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Say hi to @$name',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This is the start of your conversation.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white70,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
