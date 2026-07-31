import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
        unreadCount: _conversations[index].unreadCount + 1,
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
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: _motion,
            switchInCurve: Curves.easeInOutCubic,
            switchOutCurve: Curves.easeInOutCubic,
            child: _buildBody(),
          ),
        ),
        Positioned(right: 26, bottom: 30, child: _ComposeButton(onTap: _load)),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const _SoftLoader(key: ValueKey('loading'));
    }

    if (_error != null && _conversations.isEmpty) {
      return _ChatList(key: const ValueKey('preview'), entries: _demoEntries);
    }

    final entries = _conversations.isEmpty
        ? _demoEntries
        : _conversations.map(_ChatEntry.fromConversation).toList();

    return _ChatList(
      key: const ValueKey('chats'),
      entries: entries,
      onTap: (index) async {
        if (_conversations.isEmpty) return;
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
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
                        ),
                        if (entry.pinned) ...[
                          const SizedBox(width: 6),
                          Transform.rotate(
                            angle: 0.6,
                            child: const Icon(
                              Icons.push_pin_rounded,
                              color: _purple,
                              size: 12.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (entry.voice) ...[
                          const Icon(
                            Icons.mic_rounded,
                            color: Color(0xFFE05A63),
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            entry.preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: entry.accentPreview
                                  ? _purple
                                  : const Color(0xFF9A9AA5),
                              fontSize: 11.5,
                              height: 1.2,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
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
    this.pinned = false,
    this.voice = false,
    this.accentPreview = false,
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
  final bool pinned;
  final bool voice;
  final bool accentPreview;

  static String _formatTime(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $suffix';
  }
}

const _demoEntries = [
  _ChatEntry(
    name: 'Larry Machigo',
    preview: 'Ok. Let me check',
    time: '09:38 AM',
    avatarUrl: 'https://randomuser.me/api/portraits/men/32.jpg',
    fallback: Color(0xFF786759),
    pinned: true,
  ),
  _ChatEntry(
    name: 'Natalie Nora',
    preview: 'Natalie is typing...',
    time: '',
    avatarUrl: 'https://randomuser.me/api/portraits/women/44.jpg',
    fallback: Color(0xFF35A8AC),
    unread: 2,
    accentPreview: true,
  ),
  _ChatEntry(
    name: 'Jennifer Jones',
    preview: 'Voice message',
    time: '02:03 AM',
    avatarUrl: 'https://randomuser.me/api/portraits/women/65.jpg',
    fallback: Color(0xFFB25A59),
    voice: true,
  ),
  _ChatEntry(
    name: 'Larry Machigo',
    preview: 'See you tomorrow, take care.',
    time: 'Yesterday',
    avatarUrl: 'https://randomuser.me/api/portraits/men/75.jpg',
    fallback: Color(0xFF44647A),
  ),
  _ChatEntry(
    name: 'Sofia',
    preview: 'Oh... thank you so much',
    time: '26 May',
    avatarUrl: 'https://randomuser.me/api/portraits/women/12.jpg',
    fallback: Color(0xFF15141C),
  ),
  _ChatEntry(
    name: 'Haider Ive',
    preview: '🙏 Sticker',
    time: '12 Jun',
    avatarUrl: 'https://randomuser.me/api/portraits/men/22.jpg',
    fallback: Color(0xFF35343E),
  ),
  _ChatEntry(
    name: 'Mr. Elon',
    preview: 'Cool :-)))',
    time: '18 Jun',
    avatarUrl: 'https://randomuser.me/api/portraits/men/46.jpg',
    fallback: Color(0xFF718187),
  ),
];
