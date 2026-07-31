import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/state/auth_controller.dart';
import '../chat/data/chat_models.dart';
import '../chat/data/conversations_api.dart';
import '../chat/state/chat_providers.dart';

const _ink = Color(0xFF1B1B1B);
const _purple = Color(0xFF5D4EF5);
const _purpleEnd = Color(0xFF6C63FF);
const _motion = Duration(milliseconds: 250);

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  List<Conversation> _conversations = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    ref.listenManual(socketServiceProvider, (previous, next) {
      next?.onConversationUpdate.listen(_onConversationUpdated);
    }, fireImmediately: true);
  }

  void _onConversationUpdated(ConversationUpdateEvent event) {
    if (!mounted) return;
    // Fires for every participant, including whoever just sent the message,
    // so their own unread badge must not bump for their own message.
    final myId = ref.read(authControllerProvider).value?.user?.id;
    final isOwnMessage = event.lastMessage.senderId == myId;
    setState(() {
      final index = _conversations.indexWhere(
        (conversation) => conversation.id == event.conversationId,
      );
      if (index == -1) {
        _load();
        return;
      }
      final updated = _conversations[index].copyWith(
        lastMessage: event.lastMessage,
        unreadCount: isOwnMessage
            ? _conversations[index].unreadCount
            : _conversations[index].unreadCount + 1,
      );
      _conversations
        ..removeAt(index)
        ..insert(0, updated);
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final conversations = await ref
          .read(conversationsApiProvider)
          .fetchConversations();
      if (!mounted) return;
      setState(() => _conversations = conversations);
    } on ConversationsApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _motion,
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const _SoftLoader(key: ValueKey('loading'));
    }

    if (_error != null) {
      return _ErrorState(
        key: const ValueKey('error'),
        message: _error!,
        onRetry: _load,
      );
    }

    if (_conversations.isEmpty) {
      return const _EmptyState(key: ValueKey('empty'));
    }

    final entries = _conversations.map(_ChatEntry.fromConversation).toList();

    return _ChatList(
      key: const ValueKey('chats'),
      entries: entries,
      onTap: (index) async {
        final conversation = _conversations[index];
        await context.push(
          '/chats/${conversation.id}',
          extra: conversation.otherParticipant,
        );
        _load();
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6C63FF), Color(0xFF5D4EF5)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _purple.withValues(alpha: 0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.chat_bubble_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'No conversations yet',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: _ink,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Search for someone by username to start\nyour first chat.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Color(0xFF9A9AA5),
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: () => context.go('/search'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _purple,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  'Find people',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFFB9B9C4),
              size: 40,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Color(0xFF9A9AA5),
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _purple,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatList extends StatelessWidget {
  const _ChatList({super.key, required this.entries, this.onTap});

  final List<_ChatEntry> entries;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(26, 4, 26, 110),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        return _ChatRow(
          entry: entries[index],
          onTap: onTap == null ? null : () => onTap!(index),
        );
      },
    );
  }
}

class _ChatRow extends StatefulWidget {
  const _ChatRow({required this.entry, this.onTap});

  final _ChatEntry entry;
  final VoidCallback? onTap;

  @override
  State<_ChatRow> createState() => _ChatRowState();
}

class _ChatRowState extends State<_ChatRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => _pressed = true),
      onTapCancel: widget.onTap == null
          ? null
          : () => setState(() => _pressed = false),
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: _motion,
        curve: Curves.easeInOutCubic,
        alignment: Alignment.center,
        child: SizedBox(
          height: 62,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Avatar(entry: entry),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: _ink,
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Color(0xFF9A9AA5),
                        fontSize: 11.5,
                        height: 1.2,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 58,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      entry.time,
                      maxLines: 1,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Color(0xFFA9A9B4),
                        fontSize: 10.5,
                        height: 1.2,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 7),
                    if (entry.unread > 0)
                      Container(
                        width: 21,
                        height: 21,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _purple,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _purple.withValues(alpha: 0.32),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Text(
                          '${entry.unread}',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 10,
                            height: 1,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 21),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.entry});

  final _ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: entry.fallback,
      alignment: Alignment.center,
      child: Text(
        entry.name.characters.first.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'Poppins',
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2C2751).withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: const Color(0xFF2C2751).withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: entry.avatarUrl == null
            ? fallback
            : Image.network(
                entry.avatarUrl!,
                fit: BoxFit.cover,
                frameBuilder: (context, child, frame, _) {
                  return AnimatedSwitcher(
                    duration: _motion,
                    child: frame == null ? fallback : child,
                  );
                },
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

/// Floating purple compose button from the reference, bottom-right.
class _ComposeButton extends StatefulWidget {
  const _ComposeButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_ComposeButton> createState() => _ComposeButtonState();
}

class _ComposeButtonState extends State<_ComposeButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'New chat',
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
          curve: Curves.easeInOutCubic,
          child: Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_purpleEnd, _purple],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _purple.withValues(alpha: 0.38),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: _purple.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CustomPaint(painter: _ComposeRingPainter()),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposeRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 9),
      -1.0,
      5.0,
      false,
      paint,
    );
    canvas.drawCircle(center, 2.4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SoftLoader extends StatefulWidget {
  const _SoftLoader({super.key});

  @override
  State<_SoftLoader> createState() => _SoftLoaderState();
}

class _SoftLoaderState extends State<_SoftLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: Tween(begin: 0.35, end: 1.0).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
        ),
        child: const SizedBox(
          width: 8,
          height: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(color: _purple, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

class _ChatEntry {
  const _ChatEntry({
    required this.name,
    required this.preview,
    required this.time,
    required this.fallback,
    this.avatarUrl,
    this.unread = 0,
  });

  factory _ChatEntry.fromConversation(Conversation conversation) {
    final other = conversation.otherParticipant;
    final date = conversation.lastMessage?.createdAt;
    return _ChatEntry(
      name: other.displayName?.isNotEmpty == true
          ? other.displayName!
          : other.username,
      preview: conversation.lastMessage?.preview ?? 'Say hello',
      time: date == null ? '' : _formatTime(date),
      avatarUrl: other.avatarUrl,
      unread: conversation.unreadCount,
      fallback: const Color(0xFF7467FF),
    );
  }

  final String name;
  final String preview;
  final String time;
  final String? avatarUrl;
  final Color fallback;
  final int unread;

  static String _formatTime(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $suffix';
  }
}
