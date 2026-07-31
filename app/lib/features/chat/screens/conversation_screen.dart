import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/state/auth_controller.dart';
import '../../posts/data/post_models.dart';
import '../data/chat_models.dart';
import '../data/conversations_api.dart';
import '../state/chat_providers.dart';
import '../widgets/link_message_card.dart';

const _ink = Color(0xFF1B1B1B);
const _muted = Color(0xFF8A8A8A);
const _purple = Color(0xFF5D4EF5);

// Canvas
const _canvasBase = Color(0xFF5B4CF5);
const _canvasOverlay = Color(0xFF6F63FF);

// Send button
const _sendTop = Color(0xFF7568FF);
const _sendBottom = Color(0xFF5648F5);

const _motion = Duration(milliseconds: 250);
const _ease = Curves.easeInOutCubic;

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
  StreamSubscription<ChatMessage>? _messageUpdateSub;
  StreamSubscription<MessageRemovedEvent>? _messageRemovedSub;
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
    _messageUpdateSub = ref
        .read(socketServiceProvider)
        ?.onMessageUpdated
        .where((m) => m.conversationId == widget.conversationId)
        .listen(_replaceMessage);
    _messageRemovedSub = ref
        .read(socketServiceProvider)
        ?.onMessageRemoved
        .where((event) => event.conversationId == widget.conversationId)
        .listen((event) => _removeMessage(event.messageId));
    _typingSub = ref
        .read(socketServiceProvider)
        ?.onTyping
        .where((t) => t.userId == widget.otherParticipant.id)
        .listen(_onTyping);
    ref.read(conversationsApiProvider).markRead(widget.conversationId);
    // Marks this conversation as "open" so the global listener doesn't pop
    // a banner/sound for messages we're already looking at.
    Future.microtask(
      () => ref
          .read(activeConversationIdProvider.notifier)
          .set(widget.conversationId),
    );
  }

  @override
  void dispose() {
    ref.read(socketServiceProvider)?.leaveConversation(widget.conversationId);
    if (ref.read(activeConversationIdProvider) == widget.conversationId) {
      ref.read(activeConversationIdProvider.notifier).set(null);
    }
    _messageSub?.cancel();
    _messageUpdateSub?.cancel();
    _messageRemovedSub?.cancel();
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

  void _replaceMessage(ChatMessage message) {
    if (!mounted) return;
    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index == -1) return;
    setState(() => _messages[index] = message);
  }

  void _removeMessage(String messageId) {
    if (!mounted) return;
    setState(() => _messages.removeWhere((message) => message.id == messageId));
  }

  Future<void> _showMessageActions(ChatMessage message, bool isMine) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) =>
          _MessageActionSheet(canUnsend: isMine && !message.isUnsent),
    );
    if (!mounted || action == null) return;

    try {
      final api = ref.read(conversationsApiProvider);
      if (action == 'remove') {
        await api.removeForMe(widget.conversationId, message.id);
        _removeMessage(message.id);
      } else if (action == 'unsend') {
        _replaceMessage(
          await api.unsendMessage(widget.conversationId, message.id),
        );
      } else if (action.startsWith('react:')) {
        _replaceMessage(
          await api.reactToMessage(
            widget.conversationId,
            message.id,
            action.substring('react:'.length),
          ),
        );
      }
    } on ConversationsApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
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

  Future<void> _pickAndSendImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) return;
    await _sendAttachment(
      filePath: picked.path,
      fileName: picked.name,
      isImage: true,
    );
  }

  Future<void> _pickAndSendFile() async {
    final picked = await openFile();
    if (picked == null) return;
    await _sendAttachment(
      filePath: picked.path,
      fileName: picked.name,
      isImage: false,
    );
  }

  Future<void> _sendAttachment({
    required String filePath,
    required String fileName,
    required bool isImage,
  }) async {
    if (_isSending) return;
    setState(() => _isSending = true);
    try {
      final message = await ref
          .read(conversationsApiProvider)
          .sendAttachment(
            widget.conversationId,
            filePath: filePath,
            fileName: fileName,
            isImage: isImage,
          );
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
      backgroundColor: _canvasBase,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const Positioned.fill(child: _PremiumCanvas()),
          Column(
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
                onCamera: () => _pickAndSendImage(ImageSource.camera),
                onPhotos: () => _pickAndSendImage(ImageSource.gallery),
                onFiles: _pickAndSendFile,
              ),
            ],
          ),
        ],
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
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 18),
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
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 14),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMine = message.sender.id == myId;
        final Widget content = message.isUnsent
            ? _Bubble(text: 'This message was unsent', mine: isMine)
            : switch (message.type) {
                MessageType.link => Align(
                  alignment: isMine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: LinkMessageCard(message: message, isMine: isMine),
                  ),
                ),
                MessageType.image => _ImageBubble(
                  message: message,
                  mine: isMine,
                ),
                MessageType.file => _FileBubble(message: message, mine: isMine),
                MessageType.text => _Bubble(
                  text: message.text ?? '',
                  mine: isMine,
                ),
              };

        return _Appear(
          child: _MessageActionTarget(
            onLongPress: () => _showMessageActions(message, isMine),
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                content,
                if (!message.isUnsent && message.reactions.isNotEmpty)
                  _MessageReactionStrip(
                    reactions: message.reactions,
                    mine: isMine,
                    currentUserId: myId,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Background
// ─────────────────────────────────────────────────────────────

/// Layered purple canvas: base gradient, warm overlay, radial top light,
/// soft vignette and a whisper of surface noise so it never reads as flat.
class _PremiumCanvas extends StatelessWidget {
  const _PremiumCanvas();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [_canvasOverlay, _canvasBase],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.05, -0.85),
              radius: 1.05,
              colors: [
                Colors.white.withValues(alpha: 0.17),
                Colors.white.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.15,
              colors: [
                const Color(0xFF2A1F7A).withValues(alpha: 0.0),
                const Color(0xFF251B70).withValues(alpha: 0.22),
              ],
              stops: const [0.5, 1.0],
            ),
          ),
        ),
        const Opacity(
          opacity: 0.6,
          child: CustomPaint(painter: _NoisePainter()),
        ),
      ],
    );
  }
}

class _NoisePainter extends CustomPainter {
  const _NoisePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Fixed seed keeps the grain stable between frames.
    final random = math.Random(7);
    final light = Paint()..color = Colors.white.withValues(alpha: 0.030);
    final dark = Paint()
      ..color = const Color(0xFF1B1240).withValues(alpha: 0.030);

    for (var i = 0; i < 900; i++) {
      final dx = random.nextDouble() * size.width;
      final dy = random.nextDouble() * size.height;
      canvas.drawCircle(
        Offset(dx, dy),
        random.nextDouble() * 0.9 + 0.3,
        random.nextBool() ? light : dark,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────

/// Builds the header silhouette: symmetric organic curves on both left and
/// right, so the header feels balanced instead of asymmetric.
Path _headerPath(Size size) {
  final w = size.width;
  final h = size.height;
  return Path()
    ..moveTo(0, 0)
    ..lineTo(w, 0)
    ..lineTo(w, h - 58)
    ..cubicTo(w, h - 14, w - 15, h, w - 58, h)
    ..lineTo(58, h)
    ..cubicTo(15, h, 0, h - 14, 0, h - 58)
    ..close();
}

class _HeaderPainter extends CustomPainter {
  const _HeaderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = _headerPath(size);

    // Layered ambient shadows — no Material elevation anywhere.
    canvas.save();
    canvas.translate(0, 18);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF241C5E).withValues(alpha: 0.16)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 25),
    );
    canvas.restore();

    canvas.save();
    canvas.translate(0, 8);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF241C5E).withValues(alpha: 0.10)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 11),
    );
    canvas.restore();

    canvas.drawPath(path, Paint()..color = Colors.white);

    // Whisper of a warm inner sheen along the bottom curve.
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, size.height * 0.55),
          Offset(0, size.height),
          [
            Colors.white.withValues(alpha: 0.0),
            const Color(0xFFF3F1FF).withValues(alpha: 0.85),
          ],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

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
      color: Color(0xFFEFECFF),
      child: Icon(Icons.person_rounded, color: _purple, size: 22),
    );

    final topPad = MediaQuery.paddingOf(context).top;
    const contentHeight = 76.0;
    const tail = 22.0;

    return SizedBox(
      height: topPad + contentHeight + tail,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _HeaderPainter())),
          Positioned(
            top: topPad,
            left: 0,
            right: 0,
            height: contentHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 22, 0),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const SizedBox(
                      width: 36,
                      height: 48,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CustomPaint(painter: _BackArrowPainter()),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF2B2468,
                          ).withValues(alpha: 0.16),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                        BoxShadow(
                          color: const Color(
                            0xFF2B2468,
                          ).withValues(alpha: 0.06),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
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
                  const SizedBox(width: 12),
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
                            letterSpacing: -0.25,
                          ),
                        ),
                        const SizedBox(height: 2),
                        AnimatedSwitcher(
                          duration: _motion,
                          switchInCurve: _ease,
                          switchOutCurve: _ease,
                          child: Text(
                            isTyping ? 'typing…' : 'Online',
                            key: ValueKey(isTyping),
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: _muted,
                              fontSize: 10,
                              height: 1.2,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _OutlineCircleButton(
                    painter: const _VideoIconPainter(),
                    semanticLabel: 'Video call',
                    onTap: () => _showComingSoon(context, 'Video calls'),
                  ),
                  const SizedBox(width: 11),
                  _OutlineCircleButton(
                    painter: const _PhoneIconPainter(),
                    semanticLabel: 'Voice call',
                    onTap: () => _showComingSoon(context, 'Voice calls'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlineCircleButton extends StatefulWidget {
  const _OutlineCircleButton({
    required this.painter,
    required this.semanticLabel,
    required this.onTap,
  });

  final CustomPainter painter;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  State<_OutlineCircleButton> createState() => _OutlineCircleButtonState();
}

class _OutlineCircleButtonState extends State<_OutlineCircleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
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
          curve: _ease,
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF1B1B1B).withValues(alpha: 0.88),
                width: 1.1,
              ),
            ),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CustomPaint(painter: widget.painter),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Bubbles
// ─────────────────────────────────────────────────────────────

/// Fade + rise + settle as a bubble enters the list.
class _MessageActionTarget extends StatelessWidget {
  const _MessageActionTarget({required this.child, required this.onLongPress});

  final Widget child;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.deferToChild,
    onLongPress: onLongPress,
    child: child,
  );
}

class _MessageReactionStrip extends StatelessWidget {
  const _MessageReactionStrip({
    required this.reactions,
    required this.mine,
    required this.currentUserId,
  });

  final List<MessageReaction> reactions;
  final bool mine;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    final reactedByMe = <String>{};
    for (final reaction in reactions) {
      counts.update(reaction.emoji, (count) => count + 1, ifAbsent: () => 1);
      if (reaction.userId == currentUserId) reactedByMe.add(reaction.emoji);
    }

    return Padding(
      padding: EdgeInsets.only(
        left: mine ? 0 : 5,
        right: mine ? 5 : 0,
        bottom: 4,
      ),
      child: Wrap(
        spacing: 5,
        children: counts.entries
            .map((entry) {
              final selected = reactedByMe.contains(entry.key);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFE9E5FF)
                      : Colors.white.withValues(alpha: 0.19),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFB9B0FF)
                        : Colors.white.withValues(alpha: 0.30),
                  ),
                ),
                child: Text(
                  '${entry.key} ${entry.value}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10.5,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    color: selected ? _purple : Colors.white,
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _MessageActionSheet extends StatelessWidget {
  const _MessageActionSheet({required this.canUnsend});

  final bool canUnsend;
  static const _reactions = ['❤️', '👍', '😂', '😮', '😢'];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFDFDFF),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF17103E).withValues(alpha: 0.20),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _reactions
                  .map(
                    (emoji) => _ReactionButton(
                      emoji: emoji,
                      onTap: () => Navigator.of(context).pop('react:$emoji'),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
            _SheetAction(
              icon: Icons.visibility_off_outlined,
              label: 'Remove for me',
              onTap: () => Navigator.of(context).pop('remove'),
            ),
            if (canUnsend)
              _SheetAction(
                icon: Icons.undo_rounded,
                label: 'Unsend',
                danger: true,
                onTap: () => Navigator.of(context).pop('unsend'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Text(emoji, style: const TextStyle(fontSize: 24)),
    ),
  );
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 20, color: danger ? const Color(0xFFD94040) : _ink),
          const SizedBox(width: 13),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: danger ? const Color(0xFFD94040) : _ink,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Appear extends StatelessWidget {
  const _Appear({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: _motion,
      curve: _ease,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 10),
            child: Transform.scale(scale: 0.965 + 0.035 * t, child: child),
          ),
        );
      },
      child: child,
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.74;
    const radius = BorderRadius.all(Radius.circular(26));

    final label = Text(
      text,
      style: TextStyle(
        fontFamily: 'Poppins',
        color: mine ? const Color(0xFF241F3D) : Colors.white,
        fontSize: 12.5,
        height: 1.48,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.05,
      ),
    );

    if (mine) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.fromLTRB(18, 13, 18, 14),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFFFF), Color(0xFFF6F5FF)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E1550).withValues(alpha: 0.18),
                blurRadius: 50,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: const Color(0xFF1E1550).withValues(alpha: 0.10),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: label,
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1C1250).withValues(alpha: 0.20),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
            BoxShadow(
              color: const Color(0xFF1C1250).withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 13, 18, 14),
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.26),
                    Colors.white.withValues(alpha: 0.15),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                  width: 1,
                ),
              ),
              child: label,
            ),
          ),
        ),
      ),
    );
  }
}

/// An uploaded photo, shown as a rounded thumbnail. Tapping keeps the user
/// inside OurChat and opens a full-screen, zoomable viewer.
class _ImageBubble extends StatelessWidget {
  const _ImageBubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final url = message.linkImageUrl;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.6;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: url == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _ImageViewerScreen(imageUrl: url),
                ),
              ),
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          margin: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1C1250).withValues(alpha: 0.20),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: url == null
                ? const SizedBox(
                    width: 160,
                    height: 160,
                    child: ColoredBox(color: Color(0xFFEDEBFF)),
                  )
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => const SizedBox(
                      width: 160,
                      height: 160,
                      child: ColoredBox(color: Color(0xFFEDEBFF)),
                    ),
                    errorWidget: (_, _, _) => const SizedBox(
                      width: 160,
                      height: 160,
                      child: ColoredBox(color: Color(0xFFEDEBFF)),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen in-app photo viewer (pinch-to-zoom) with a save-to-device
/// action — tapping a photo bubble opens this instead of handing the image
/// off to an external browser/viewer.
class _ImageViewerScreen extends StatefulWidget {
  const _ImageViewerScreen({required this.imageUrl});

  final String imageUrl;

  @override
  State<_ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<_ImageViewerScreen> {
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await DefaultCacheManager().getSingleFile(widget.imageUrl);
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await Gal.putImage(file.path, album: 'OurChat');
      } else {
        final location = await getSaveLocation(
          suggestedName: file.uri.pathSegments.last,
        );
        if (location == null) return; // user cancelled the save dialog
        await file.copy(location.path);
      }
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not save the image')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Save picture',
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_rounded),
            onPressed: _save,
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: CachedNetworkImage(
            imageUrl: widget.imageUrl,
            fit: BoxFit.contain,
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(_saving ? 'Saving…' : 'Save picture'),
          ),
        ),
      ),
    );
  }
}

/// An uploaded arbitrary file — a bubble with a file-type icon, name and
/// human-readable size. Tapping downloads/opens it externally.
class _FileBubble extends StatelessWidget {
  const _FileBubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  String get _sizeLabel {
    final bytes = message.fileSize;
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.74;
    const radius = BorderRadius.all(Radius.circular(22));
    final url = message.linkUrl;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: mine
                ? const Color(0xFFEFECFF)
                : Colors.white.withValues(alpha: 0.22),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.insert_drive_file_rounded,
            size: 19,
            color: mine ? _purple : Colors.white,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.linkTitle ?? 'File',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: mine ? const Color(0xFF241F3D) : Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_sizeLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  _sizeLabel,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: mine ? _muted : Colors.white.withValues(alpha: 0.75),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: url == null
            ? null
            : () => launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              ),
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: mine
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFFFFF), Color(0xFFF6F5FF)],
                  )
                : null,
            color: mine ? null : Colors.white.withValues(alpha: 0.14),
            border: mine
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.22)),
            boxShadow: mine
                ? [
                    BoxShadow(
                      color: const Color(0xFF1E1550).withValues(alpha: 0.18),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ]
                : null,
          ),
          child: content,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Composer
// ─────────────────────────────────────────────────────────────

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.isSending,
    required this.onSend,
    required this.onTypingChanged,
    required this.onCamera,
    required this.onPhotos,
    required this.onFiles,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;
  final ValueChanged<String> onTypingChanged;
  final VoidCallback onCamera;
  final VoidCallback onPhotos;
  final VoidCallback onFiles;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus != _focused) {
        setState(() => _focused = _focusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: _motion,
                curve: _ease,
                constraints: const BoxConstraints(minHeight: 64),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFFFFF), Color(0xFFFAF9FF)],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.9),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(
                        0xFF1E1550,
                      ).withValues(alpha: _focused ? 0.22 : 0.16),
                      blurRadius: 50,
                      offset: const Offset(0, 18),
                    ),
                    BoxShadow(
                      color: const Color(0xFF1E1550).withValues(alpha: 0.08),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(11, 0, 0, 13),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showComingSoon(context, 'Voice messages'),
                        child: Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFF3F1FF), Color(0xFFEBE8FF)],
                            ),
                          ),
                          child: const SizedBox(
                            width: 20,
                            height: 20,
                            child: CustomPaint(painter: _MicIconPainter()),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _focusNode,
                        minLines: 1,
                        maxLines: 4,
                        cursorColor: _purple,
                        cursorWidth: 1.6,
                        cursorRadius: const Radius.circular(2),
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: _ink,
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w400,
                        ),
                        onChanged: widget.onTypingChanged,
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: false,
                          hintText: 'Type a message',
                          hintStyle: TextStyle(
                            fontFamily: 'Poppins',
                            color: Color(0xFFA5A2B8),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.1,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.fromLTRB(12, 23, 0, 23),
                        ),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => showAttachmentSheet(
                        context,
                        onCamera: widget.onCamera,
                        onPhotos: widget.onPhotos,
                        onFiles: widget.onFiles,
                      ),
                      child: const SizedBox(
                        width: 48,
                        height: 64,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CustomPaint(painter: _ClipIconPainter()),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            _SendButton(isSending: widget.isSending, onPressed: widget.onSend),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Attachment sheet
// ─────────────────────────────────────────────────────────────

/// Bottom sheet offering Camera / Photos / Files, with a hand-tuned
/// slide+fade entrance (built on showGeneralDialog rather than the stock
/// modal bottom sheet, for full control over the curve) and a spring-back
/// press animation on each option.
Future<void> showAttachmentSheet(
  BuildContext context, {
  required VoidCallback onCamera,
  required VoidCallback onPhotos,
  required VoidCallback onFiles,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierLabel: 'Attach',
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.38),
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _AttachmentSheet(
        onCamera: onCamera,
        onPhotos: onPhotos,
        onFiles: onFiles,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

class _AttachmentSheet extends StatelessWidget {
  const _AttachmentSheet({
    required this.onCamera,
    required this.onPhotos,
    required this.onFiles,
  });

  final VoidCallback onCamera;
  final VoidCallback onPhotos;
  final VoidCallback onFiles;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.fromLTRB(8, 22, 8, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1E1550).withValues(alpha: 0.28),
                  blurRadius: 50,
                  offset: const Offset(0, 20),
                ),
                BoxShadow(
                  color: const Color(0xFF1E1550).withValues(alpha: 0.14),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7E4F5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _AttachmentOption(
                        icon: Icons.camera_alt_rounded,
                        label: 'Camera',
                        onTap: () {
                          Navigator.of(context).pop();
                          onCamera();
                        },
                      ),
                      _AttachmentOption(
                        icon: Icons.photo_library_rounded,
                        label: 'Photos',
                        onTap: () {
                          Navigator.of(context).pop();
                          onPhotos();
                        },
                      ),
                      _AttachmentOption(
                        icon: Icons.insert_drive_file_rounded,
                        label: 'Files',
                        onTap: () {
                          Navigator.of(context).pop();
                          onFiles();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentOption extends StatefulWidget {
  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_AttachmentOption> createState() => _AttachmentOptionState();
}

class _AttachmentOptionState extends State<_AttachmentOption> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.90 : 1,
        duration: _pressed
            ? const Duration(milliseconds: 110)
            : const Duration(milliseconds: 320),
        curve: _pressed ? Curves.easeOut : Curves.elasticOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF8B7DFF), Color(0xFF5D4EF5)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _purple.withValues(alpha: 0.32),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(widget.icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              widget.label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: _ink,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Polished glass send button — the focal point of the screen.
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
    return Semantics(
      button: true,
      label: 'Send message',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          if (!widget.isSending) widget.onPressed();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: _pressed
              ? const Duration(milliseconds: 120)
              : const Duration(milliseconds: 420),
          curve: _pressed ? Curves.easeOut : Curves.elasticOut,
          child: AnimatedContainer(
            duration: _motion,
            curve: _ease,
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_sendTop, _sendBottom],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.20),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF3A2BC9,
                  ).withValues(alpha: _pressed ? 0.28 : 0.46),
                  blurRadius: _pressed ? 18 : 30,
                  offset: Offset(0, _pressed ? 7 : 16),
                ),
                BoxShadow(
                  color: const Color(
                    0xFF1E1550,
                  ).withValues(alpha: _pressed ? 0.10 : 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Top highlight, like light catching polished glass.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.15, -0.65),
                        radius: 0.85,
                        colors: [
                          Colors.white.withValues(alpha: 0.38),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: _motion,
                  switchInCurve: _ease,
                  switchOutCurve: _ease,
                  child: widget.isSending
                      ? const SizedBox(
                          key: ValueKey('sending'),
                          width: 9,
                          height: 9,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                      : const Padding(
                          key: ValueKey('send'),
                          padding: EdgeInsets.only(left: 3),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CustomPaint(painter: _SendArrowPainter()),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Thin custom icons
// ─────────────────────────────────────────────────────────────

Paint _stroke(Color color, [double width = 1.5]) => Paint()
  ..color = color
  ..strokeWidth = width
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

class _BackArrowPainter extends CustomPainter {
  const _BackArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = _stroke(_ink, 1.7);
    canvas.drawLine(const Offset(4.0, 10), const Offset(16.5, 10), p);
    canvas.drawPath(
      Path()
        ..moveTo(9.6, 4.6)
        ..lineTo(4.0, 10)
        ..lineTo(9.6, 15.4),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _VideoIconPainter extends CustomPainter {
  const _VideoIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = _stroke(_ink, 1.4);
    canvas.drawRRect(
      RRect.fromLTRBR(2.2, 6.0, 13.0, 14.6, const Radius.circular(2.8)),
      p,
    );
    canvas.drawPath(
      Path()
        ..moveTo(17.6, 6.9)
        ..lineTo(13.6, 9.4)
        ..lineTo(13.6, 11.2)
        ..lineTo(17.6, 13.7)
        ..close(),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PhoneIconPainter extends CustomPainter {
  const _PhoneIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = _stroke(_ink, 1.4);
    canvas.drawPath(
      Path()
        ..moveTo(6.6, 3.1)
        ..quadraticBezierTo(4.5, 3.0, 3.9, 5.0)
        ..cubicTo(2.9, 10.4, 9.1, 16.9, 14.7, 16.2)
        ..quadraticBezierTo(16.8, 15.9, 16.7, 13.8)
        ..lineTo(16.6, 12.5)
        ..quadraticBezierTo(16.5, 11.7, 15.7, 11.6)
        ..lineTo(13.3, 11.2)
        ..quadraticBezierTo(12.6, 11.1, 12.2, 11.7)
        ..lineTo(11.4, 12.8)
        ..cubicTo(9.7, 11.9, 8.2, 10.4, 7.3, 8.6)
        ..lineTo(8.4, 7.8)
        ..quadraticBezierTo(9.0, 7.4, 8.9, 6.7)
        ..lineTo(8.5, 4.3)
        ..quadraticBezierTo(8.4, 3.5, 7.6, 3.4)
        ..close(),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MicIconPainter extends CustomPainter {
  const _MicIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = _stroke(_purple, 1.5);
    canvas.drawRRect(
      RRect.fromLTRBR(7.3, 2.4, 12.7, 11.4, const Radius.circular(2.7)),
      p,
    );
    canvas.drawArc(
      const Rect.fromLTRB(4.6, 6.2, 15.4, 15.4),
      0,
      math.pi,
      false,
      p,
    );
    canvas.drawLine(const Offset(10, 13.6), const Offset(10, 17.2), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ClipIconPainter extends CustomPainter {
  const _ClipIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = _stroke(const Color(0xFFA5A2B8), 1.5);
    canvas.drawPath(
      Path()
        ..moveTo(14.3, 6.6)
        ..lineTo(7.6, 13.3)
        ..quadraticBezierTo(6.1, 14.8, 7.5, 16.1)
        ..quadraticBezierTo(8.9, 17.4, 10.4, 15.9)
        ..lineTo(16.4, 9.9)
        ..quadraticBezierTo(18.9, 7.4, 16.3, 4.9)
        ..quadraticBezierTo(13.7, 2.4, 11.2, 4.9)
        ..lineTo(5.0, 11.1),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SendArrowPainter extends CustomPainter {
  const _SendArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(6.0, 3.6)
      ..lineTo(16.6, 11.0)
      ..lineTo(6.0, 18.4)
      ..close();
    // Fill plus a matching round-joined stroke softens the triangle's points.
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(path, _stroke(Colors.white, 3.2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────
// States
// ─────────────────────────────────────────────────────────────

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1E1550).withValues(alpha: 0.20),
              blurRadius: 40,
              offset: const Offset(0, 14),
            ),
          ],
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
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1C1250).withValues(alpha: 0.18),
                    blurRadius: 34,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: const Icon(
                Icons.waving_hand_rounded,
                color: Colors.white,
                size: 27,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Say hi to @$name',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This is the start of your conversation.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
