import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/state/auth_controller.dart';
import '../../posts/data/post_models.dart';
import '../data/chat_models.dart';
import '../data/conversations_api.dart';
import '../state/chat_providers.dart';

const _ink = Color(0xFF1B1B1B);
const _muted = Color(0xFF8A8A8A);
const _purple = Color(0xFF5D4EF5);
const _canvas = Color(0xFFF7F7FF);
const _motion = Duration(milliseconds: 250);
const _ease = Curves.easeInOutCubic;

class ConversationDetailsScreen extends ConsumerStatefulWidget {
  const ConversationDetailsScreen({
    super.key,
    required this.conversationId,
    required this.otherParticipant,
  });

  final String conversationId;
  final PostAuthor otherParticipant;

  @override
  ConsumerState<ConversationDetailsScreen> createState() =>
      _ConversationDetailsScreenState();
}

class _ConversationDetailsScreenState
    extends ConsumerState<ConversationDetailsScreen> {
  final _scrollController = ScrollController();
  final _photos = <ChatMessage>[];
  final _links = <ChatMessage>[];
  String? _photoCursor;
  String? _linkCursor;
  bool _showPhotos = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _mutedMessages = false;
  bool _mutedCalls = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String get _name => widget.otherParticipant.displayName?.isNotEmpty == true
      ? widget.otherParticipant.displayName!
      : '@${widget.otherParticipant.username}';

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ref
            .read(conversationsApiProvider)
            .fetchConversation(widget.conversationId),
        ref
            .read(conversationsApiProvider)
            .fetchSharedMessages(widget.conversationId, photos: true),
        ref
            .read(conversationsApiProvider)
            .fetchSharedMessages(widget.conversationId, photos: false),
      ]);
      if (!mounted) return;
      final conversation = results[0] as Conversation;
      final photos = results[1] as MessagesPage;
      final links = results[2] as MessagesPage;
      setState(() {
        _mutedMessages = conversation.mutedMessages;
        _mutedCalls = conversation.mutedCalls;
        _photos
          ..clear()
          ..addAll(photos.messages);
        _links
          ..clear()
          ..addAll(links.messages);
        _photoCursor = photos.nextCursor;
        _linkCursor = links.nextCursor;
      });
    } on ConversationsApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 360) _loadMore();
  }

  Future<void> _loadMore() async {
    final cursor = _showPhotos ? _photoCursor : _linkCursor;
    if (_loadingMore || cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(conversationsApiProvider)
          .fetchSharedMessages(
            widget.conversationId,
            photos: _showPhotos,
            cursor: cursor,
          );
      if (!mounted) return;
      setState(() {
        final target = _showPhotos ? _photos : _links;
        final known = target.map((message) => message.id).toSet();
        target.addAll(page.messages.where((message) => known.add(message.id)));
        if (_showPhotos) {
          _photoCursor = page.nextCursor;
        } else {
          _linkCursor = page.nextCursor;
        }
      });
    } on ConversationsApiException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _setMute({bool? messages, bool? calls}) async {
    final previousMessages = _mutedMessages;
    final previousCalls = _mutedCalls;
    setState(() {
      if (messages != null) _mutedMessages = messages;
      if (calls != null) _mutedCalls = calls;
    });
    ref
        .read(socketServiceProvider)
        ?.setConversationMuted(
          widget.conversationId,
          messages: messages,
          calls: calls,
        );
    try {
      await ref
          .read(conversationsApiProvider)
          .setMuted(widget.conversationId, messages: messages, calls: calls);
    } on ConversationsApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _mutedMessages = previousMessages;
        _mutedCalls = previousCalls;
      });
      ref
          .read(socketServiceProvider)
          ?.setConversationMuted(
            widget.conversationId,
            messages: previousMessages,
            calls: previousCalls,
          );
      _showError(error.message);
    }
  }

  Future<void> _openMute() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _MuteSheet(
        name: _name,
        mutedMessages: _mutedMessages,
        mutedCalls: _mutedCalls,
        onMessagesChanged: (value) => _setMute(messages: value),
        onCallsChanged: (value) => _setMute(calls: value),
      ),
    );
    if (mounted) setState(() {});
  }

  void _showOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF251C60).withValues(alpha: 0.15),
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetAction(
                icon: Icons.person_outline_rounded,
                label: 'View profile',
                onTap: () {
                  Navigator.pop(context);
                  this.context.push(
                    '/search/${widget.otherParticipant.username}',
                  );
                },
              ),
              _SheetAction(
                icon: Icons.alternate_email_rounded,
                label: 'Copy username',
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: '@${widget.otherParticipant.username}'),
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  _showError('Username copied');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(onBack: () => Navigator.maybePop(context)),
            Expanded(
              child: RefreshIndicator(
                color: _purple,
                onRefresh: _loadInitial,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          _ProfileIdentity(
                            name: _name,
                            username: '@${widget.otherParticipant.username}',
                            avatarUrl: widget.otherParticipant.avatarUrl,
                          ),
                          const SizedBox(height: 25),
                          _ActionStrip(
                            muted: _mutedMessages || _mutedCalls,
                            onProfile: () => context.push(
                              '/search/${widget.otherParticipant.username}',
                            ),
                            onSearch: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ConversationSearchScreen(
                                  conversationId: widget.conversationId,
                                  otherParticipant: widget.otherParticipant,
                                ),
                              ),
                            ),
                            onMute: _openMute,
                            onOptions: _showOptions,
                          ),
                          const SizedBox(height: 32),
                          _MediaTabs(
                            photos: _showPhotos,
                            onChanged: (photos) {
                              if (_showPhotos == photos) return;
                              setState(() => _showPhotos = photos);
                              if (_scrollController.hasClients) {
                                _scrollController.animateTo(
                                  0,
                                  duration: _motion,
                                  curve: _ease,
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                    if (_loading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: CircularProgressIndicator(color: _purple),
                        ),
                      )
                    else if (_error != null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _LoadError(
                          message: _error!,
                          retry: _loadInitial,
                        ),
                      )
                    else if (_showPhotos)
                      _photoSliver()
                    else
                      _linkSliver(),
                    if (_loadingMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _purple,
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 30)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoSliver() {
    if (_photos.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyMedia(
          icon: Icons.photo_library_outlined,
          title: 'No shared photos yet',
          subtitle: 'Photos sent in this conversation will appear here.',
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      sliver: SliverGrid.builder(
        itemCount: _photos.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 3,
          mainAxisSpacing: 3,
        ),
        itemBuilder: (context, index) {
          final url = _photos[index].linkImageUrl;
          return GestureDetector(
            onTap: url == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SharedPhotoViewer(imageUrl: url),
                    ),
                  ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: url == null
                  ? const ColoredBox(color: Color(0xFFE9E7F8))
                  : CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          const ColoredBox(color: Color(0xFFE9E7F8)),
                      errorWidget: (_, _, _) => const ColoredBox(
                        color: Color(0xFFE9E7F8),
                        child: Icon(Icons.broken_image_outlined, color: _muted),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _linkSliver() {
    if (_links.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyMedia(
          icon: Icons.link_rounded,
          title: 'No shared links yet',
          subtitle: 'Links sent in this conversation will appear here.',
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      sliver: SliverList.separated(
        itemCount: _links.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) =>
            _SharedLinkTile(message: _links[index]),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onBack,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.arrow_back_rounded, size: 26, color: _ink),
        ),
      ),
    ),
  );
}

class _ProfileIdentity extends StatelessWidget {
  const _ProfileIdentity({
    required this.name,
    required this.username,
    required this.avatarUrl,
  });
  final String name;
  final String username;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 112,
        height: 112,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFE9E6FF),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2C245F).withValues(alpha: 0.14),
              blurRadius: 35,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: ClipOval(
          child: avatarUrl == null
              ? const Icon(Icons.person_rounded, size: 48, color: _purple)
              : CachedNetworkImage(
                  imageUrl: avatarUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const Icon(
                    Icons.person_rounded,
                    size: 48,
                    color: _purple,
                  ),
                ),
        ),
      ),
      const SizedBox(height: 18),
      Text(
        name,
        style: const TextStyle(
          fontFamily: 'Poppins',
          color: _ink,
          fontSize: 24,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        username,
        style: const TextStyle(
          fontFamily: 'Poppins',
          color: _muted,
          fontSize: 12,
        ),
      ),
    ],
  );
}

class _ActionStrip extends StatelessWidget {
  const _ActionStrip({
    required this.muted,
    required this.onProfile,
    required this.onSearch,
    required this.onMute,
    required this.onOptions,
  });
  final bool muted;
  final VoidCallback onProfile;
  final VoidCallback onSearch;
  final VoidCallback onMute;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _RoundAction(
          icon: Icons.person_outline_rounded,
          label: 'Profile',
          onTap: onProfile,
        ),
        _RoundAction(
          icon: Icons.search_rounded,
          label: 'Search',
          onTap: onSearch,
        ),
        _RoundAction(
          icon: muted
              ? Icons.notifications_off_rounded
              : Icons.notifications_none_rounded,
          label: muted ? 'Muted' : 'Mute',
          selected: muted,
          onTap: onMute,
        ),
        _RoundAction(
          icon: Icons.more_horiz_rounded,
          label: 'Options',
          onTap: onOptions,
        ),
      ],
    ),
  );
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: SizedBox(
      width: 70,
      child: Column(
        children: [
          AnimatedContainer(
            duration: _motion,
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: selected ? _purple : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? _purple : const Color(0xFFE6E4F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2A225D).withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Icon(icon, size: 24, color: selected ? Colors.white : _ink),
          ),
          const SizedBox(height: 9),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: _ink,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MediaTabs extends StatelessWidget {
  const _MediaTabs({required this.photos, required this.onChanged});
  final bool photos;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 51,
    margin: const EdgeInsets.symmetric(horizontal: 18),
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(25),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF2B245D).withValues(alpha: 0.07),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        _MediaTab(
          icon: Icons.photo_library_outlined,
          label: 'Photos',
          selected: photos,
          onTap: () => onChanged(true),
        ),
        _MediaTab(
          icon: Icons.link_rounded,
          label: 'Links',
          selected: !photos,
          onTap: () => onChanged(false),
        ),
      ],
    ),
  );
}

class _MediaTab extends StatelessWidget {
  const _MediaTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: _motion,
        curve: _ease,
        decoration: BoxDecoration(
          color: selected ? _purple : Colors.transparent,
          borderRadius: BorderRadius.circular(21),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? Colors.white : _muted),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: selected ? Colors.white : _muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SharedLinkTile extends StatelessWidget {
  const _SharedLinkTile({required this.message});
  final ChatMessage message;

  String? get _url {
    if (message.linkUrl?.isNotEmpty == true) return message.linkUrl;
    final match = RegExp(
      r'https?://[^\s]+',
      caseSensitive: false,
    ).firstMatch(message.text ?? '');
    if (match == null) return null;
    return match.group(0)?.replaceFirst(RegExp(r'[.,!?;:]+$'), '');
  }

  String get _domain {
    final uri = Uri.tryParse(_url ?? '');
    return uri?.host.replaceFirst('www.', '') ?? 'Shared link';
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () async {
      final uri = Uri.tryParse(_url ?? '');
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    },
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAE8F3)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: SizedBox(
              width: 58,
              height: 58,
              child: message.linkImageUrl == null
                  ? const ColoredBox(
                      color: Color(0xFFEFEDFF),
                      child: Icon(Icons.link_rounded, color: _purple),
                    )
                  : CachedNetworkImage(
                      imageUrl: message.linkImageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const ColoredBox(
                        color: Color(0xFFEFEDFF),
                        child: Icon(Icons.link_rounded, color: _purple),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.linkTitle ?? message.text ?? _url ?? 'Shared link',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: _ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: _muted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: _muted),
        ],
      ),
    ),
  );
}

class _EmptyMedia extends StatelessWidget {
  const _EmptyMedia({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 38, color: const Color(0xFFBBB6DA)),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: _ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: _muted,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        TextButton(onPressed: retry, child: const Text('Try again')),
      ],
    ),
  );
}

class _MuteSheet extends StatefulWidget {
  const _MuteSheet({
    required this.name,
    required this.mutedMessages,
    required this.mutedCalls,
    required this.onMessagesChanged,
    required this.onCallsChanged,
  });
  final String name;
  final bool mutedMessages;
  final bool mutedCalls;
  final ValueChanged<bool> onMessagesChanged;
  final ValueChanged<bool> onCallsChanged;

  @override
  State<_MuteSheet> createState() => _MuteSheetState();
}

class _MuteSheetState extends State<_MuteSheet> {
  late bool messages = widget.mutedMessages;
  late bool calls = widget.mutedCalls;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mute ${widget.name}',
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          _MuteRow(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Message notifications',
            value: messages,
            onChanged: (value) {
              setState(() => messages = value);
              widget.onMessagesChanged(value);
            },
          ),
          _MuteRow(
            icon: Icons.call_outlined,
            label: 'Call notifications',
            value: calls,
            onChanged: (value) {
              setState(() => calls = value);
              widget.onCallsChanged(value);
            },
          ),
        ],
      ),
    ),
  );
}

class _MuteRow extends StatelessWidget {
  const _MuteRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, color: _ink, size: 22),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: _ink,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Switch.adaptive(
          value: value,
          activeTrackColor: _purple,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: SizedBox(
      height: 54,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Icon(icon, color: _ink, size: 22),
          const SizedBox(width: 14),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: _ink,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

class ConversationSearchScreen extends ConsumerStatefulWidget {
  const ConversationSearchScreen({
    super.key,
    required this.conversationId,
    required this.otherParticipant,
  });
  final String conversationId;
  final PostAuthor otherParticipant;

  @override
  ConsumerState<ConversationSearchScreen> createState() =>
      _ConversationSearchScreenState();
}

class _ConversationSearchScreenState
    extends ConsumerState<ConversationSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<ChatMessage> _results = const [];
  bool _searching = false;
  String? _error;
  int _generation = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _generation++;
      setState(() {
        _searching = false;
        _results = const [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 320), () => _search(query));
  }

  Future<void> _search(String query) async {
    final generation = ++_generation;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(conversationsApiProvider)
          .searchMessages(widget.conversationId, query, take: 60);
      if (!mounted || generation != _generation) return;
      setState(() => _results = page.messages);
    } on ConversationsApiException catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _searching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.read(authControllerProvider).value?.user?.id;
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 18, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF2B245D,
                            ).withValues(alpha: 0.07),
                            blurRadius: 18,
                            offset: const Offset(0, 7),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search_rounded,
                            color: _muted,
                            size: 21,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              autofocus: true,
                              onChanged: _changed,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Search this conversation',
                                hintStyle: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Color(0xFFAAA7BA),
                                  fontSize: 12,
                                ),
                              ),
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: _ink,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_searching)
              const LinearProgressIndicator(
                minHeight: 2,
                color: _purple,
                backgroundColor: Colors.transparent,
              ),
            Expanded(
              child: _error != null
                  ? _LoadError(
                      message: _error!,
                      retry: () => _search(_controller.text.trim()),
                    )
                  : _controller.text.trim().isEmpty
                  ? const _EmptyMedia(
                      icon: Icons.search_rounded,
                      title: 'Search your messages',
                      subtitle:
                          'Find words, phrases, and links shared in this chat.',
                    )
                  : !_searching && _results.isEmpty
                  ? const _EmptyMedia(
                      icon: Icons.manage_search_rounded,
                      title: 'No results found',
                      subtitle: 'Try a different word or phrase.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                      itemCount: _results.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 9),
                      itemBuilder: (context, index) {
                        final message = _results[index];
                        final mine = message.sender.id == myId;
                        final sender = mine
                            ? 'You'
                            : message.sender.displayName?.isNotEmpty == true
                            ? message.sender.displayName!
                            : '@${message.sender.username}';
                        return Container(
                          padding: const EdgeInsets.fromLTRB(15, 13, 15, 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFEAE8F3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    sender,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      color: mine ? _purple : _ink,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _longDate(message.createdAt),
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      color: _muted,
                                      fontSize: 9.5,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                message.text ??
                                    message.linkTitle ??
                                    message.linkUrl ??
                                    'Shared message',
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  color: _ink,
                                  fontSize: 12.5,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

String _longDate(DateTime date) {
  final value = date.toLocal();
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour < 12 ? 'AM' : 'PM';
  return '${value.day}/${value.month}/${value.year} · $hour:$minute $period';
}

class SharedPhotoViewer extends StatefulWidget {
  const SharedPhotoViewer({super.key, required this.imageUrl});
  final String imageUrl;

  @override
  State<SharedPhotoViewer> createState() => _SharedPhotoViewerState();
}

class _SharedPhotoViewerState extends State<SharedPhotoViewer> {
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final file = await DefaultCacheManager().getSingleFile(widget.imageUrl);
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await Gal.putImage(file.path, album: 'OurChat');
      } else {
        final location = await getSaveLocation(
          suggestedName: file.uri.pathSegments.last,
        );
        if (location == null) return;
        await File(file.path).copy(location.path);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved to your device')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save this photo')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 12,
            child: _ViewerButton(
              icon: Icons.arrow_back_rounded,
              onTap: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            top: 10,
            right: 12,
            child: _ViewerButton(
              icon: Icons.download_rounded,
              loading: _saving,
              onTap: _save,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ViewerButton extends StatelessWidget {
  const _ViewerButton({
    required this.icon,
    required this.onTap,
    this.loading = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: loading ? null : onTap,
    child: Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(13),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, color: Colors.white, size: 23),
    ),
  );
}
