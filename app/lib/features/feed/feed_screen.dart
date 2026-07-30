import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../posts/data/post_models.dart';
import '../posts/data/posts_api.dart';
import '../posts/state/posts_providers.dart';
import '../posts/widgets/post_card.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _scrollController = ScrollController();
  final List<Post> _posts = [];
  String? _nextCursor;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFeed(reset: true);
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

  Future<void> _loadFeed({required bool reset}) async {
    setState(() {
      _isLoading = reset;
      _error = null;
    });
    try {
      final page = await ref.read(postsApiProvider).fetchFeed();
      setState(() {
        _posts
          ..clear()
          ..addAll(page.posts);
        _nextCursor = page.nextCursor;
      });
    } on PostsApiException catch (e) {
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
          .read(postsApiProvider)
          .fetchFeed(cursor: _nextCursor);
      setState(() {
        _posts.addAll(page.posts);
        _nextCursor = page.nextCursor;
      });
    } on PostsApiException {
      // Silently ignore load-more failures; the user can retry by scrolling.
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _toggleLike(Post post) async {
    final index = _posts.indexWhere((p) => p.id == post.id);
    if (index == -1) return;

    final optimistic = post.copyWith(
      likedByMe: !post.likedByMe,
      likeCount: post.likedByMe ? post.likeCount - 1 : post.likeCount + 1,
    );
    setState(() => _posts[index] = optimistic);

    try {
      final api = ref.read(postsApiProvider);
      final result = post.likedByMe
          ? await api.unlike(post.id)
          : await api.like(post.id);
      if (!mounted) return;
      final freshIndex = _posts.indexWhere((p) => p.id == post.id);
      if (freshIndex != -1) {
        setState(
          () => _posts[freshIndex] = _posts[freshIndex].copyWith(
            likedByMe: result.likedByMe,
            likeCount: result.likeCount,
          ),
        );
      }
    } on PostsApiException {
      if (!mounted) return;
      final revertIndex = _posts.indexWhere((p) => p.id == post.id);
      if (revertIndex != -1) setState(() => _posts[revertIndex] = post);
    }
  }

  Future<void> _openUploadPost() async {
    final created = await context.push<bool>('/upload-post');
    if (created == true) {
      _loadFeed(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feed')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openUploadPost,
        child: const Icon(Icons.add_a_photo),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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
            OutlinedButton(
              onPressed: () => _loadFeed(reset: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadFeed(reset: true),
        child: ListView(
          children: const [
            Padding(
              padding: EdgeInsets.only(top: 120),
              child: Center(
                child: Text('No posts yet. Be the first to share one!'),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadFeed(reset: true),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _posts.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _posts.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final post = _posts[index];
          return PostCard(
            post: post,
            onToggleLike: () => _toggleLike(post),
            onOpen: () => context.push('/feed/${post.id}'),
            onOpenAuthor: () =>
                context.push('/search/${post.author.username}'),
          );
        },
      ),
    );
  }
}
