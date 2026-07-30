import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 0),
      itemCount: _posts.length + 1 + (_isLoadingMore ? 1 : 0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _ProfileHeader(profile: profile, postCount: _posts.length);
        }
        final postIndex = index - 1;
        if (postIndex >= _posts.length) {
          return const Center(child: CircularProgressIndicator());
        }
        final post = _posts[postIndex];
        return GestureDetector(
          onTap: () => context.push('/search/${widget.username}/${post.id}'),
          child: CachedNetworkImage(
            imageUrl: post.imageUrl,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.postCount});

  final PublicProfile profile;
  final int postCount;

  @override
  Widget build(BuildContext context) {
    return GridTile(
      child: Container(),
    ).._unused(); // placeholder to satisfy GridView item typing below
  }
}

extension on Widget {
  void _unused() {}
}
