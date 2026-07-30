import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/state/auth_controller.dart';
import '../../chat/data/conversations_api.dart';
import '../../chat/state/chat_providers.dart';
import '../../posts/data/post_models.dart';
import '../data/public_profile.dart';
import '../data/users_api.dart';
import '../state/users_providers.dart';

class PublicProfileScreen extends ConsumerStatefulWidget {
  const PublicProfileScreen({super.key, required this.username});

  final String username;

  @override
  ConsumerState<PublicProfileScreen> createState() =>
      _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  final _scrollController = ScrollController();
  PublicProfile? _profile;
  final List<Post> _posts = [];
  String? _nextCursor;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final threshold = _scrollController.position.maxScrollExtent - 300;
    if (_scrollController.position.pixels >= threshold) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(usersApiProvider);
      final profile = await api.fetchProfile(widget.username);
      final page = await api.fetchUserPosts(widget.username);
      setState(() {
        _profile = profile;
        _posts
          ..clear()
          ..addAll(page.posts);
        _nextCursor = page.nextCursor;
      });
    } on UsersApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _nextCursor == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = await ref
          .read(usersApiProvider)
          .fetchUserPosts(widget.username, cursor: _nextCursor);
      setState(() {
        _posts.addAll(page.posts);
        _nextCursor = page.nextCursor;
      });
    } on UsersApiException {
      // Silently ignore load-more failures; the user can retry by scrolling.
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('@${widget.username}')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _profile == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error ?? 'User not found'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final profile = _profile!;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(child: _ProfileHeader(profile: profile, postCount: _posts.length)),
        if (_posts.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: Text('No posts yet')),
            ),
          )
        else
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final post = _posts[index];
                return GestureDetector(
                  onTap: () =>
                      context.push('/search/${widget.username}/${post.id}'),
                  child: CachedNetworkImage(
                    imageUrl: post.imageUrl,
                    fit: BoxFit.cover,
                  ),
                );
              },
              childCount: _posts.length,
            ),
          ),
        if (_isLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

class _ProfileHeader extends ConsumerStatefulWidget {
  const _ProfileHeader({required this.profile, required this.postCount});

  final PublicProfile profile;
  final int postCount;

  @override
  ConsumerState<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends ConsumerState<_ProfileHeader> {
  bool _isStartingChat = false;

  Future<void> _messageUser() async {
    setState(() => _isStartingChat = true);
    try {
      final conversation = await ref
          .read(conversationsApiProvider)
          .startConversation(widget.profile.username);
      if (!mounted) return;
      await context.push(
        '/chats/${conversation.id}',
        extra: conversation.otherParticipant,
      );
    } on ConversationsApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _isStartingChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final myId = ref.watch(authControllerProvider).value?.user?.id;
    final isMe = profile.id == myId;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          CircleAvatar(
            radius: 48,
            backgroundImage: profile.avatarUrl != null
                ? CachedNetworkImageProvider(profile.avatarUrl!)
                : null,
            child: profile.avatarUrl == null
                ? const Icon(Icons.person, size: 48)
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            '@${profile.username}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (profile.displayName != null && profile.displayName!.isNotEmpty)
            Text(profile.displayName!),
          if (profile.bio != null && profile.bio!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(profile.bio!, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 12),
          Text('${widget.postCount} posts'),
          if (!isMe) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isStartingChat ? null : _messageUser,
              icon: _isStartingChat
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chat_bubble_outline),
              label: const Text('Message'),
            ),
          ],
        ],
      ),
    );
  }
}
