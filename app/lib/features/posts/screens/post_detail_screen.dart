import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/post_models.dart';
import '../data/posts_api.dart';
import '../state/posts_providers.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _commentController = TextEditingController();
  Post? _post;
  List<PostComment> _comments = [];
  bool _isLoading = true;
  bool _isPostingComment = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(postsApiProvider);
      final post = await api.fetchPost(widget.postId);
      final commentsPage = await api.fetchComments(widget.postId);
      setState(() {
        _post = post;
        _comments = commentsPage.comments;
      });
    } on PostsApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleLike() async {
    final post = _post;
    if (post == null) return;

    final optimistic = post.copyWith(
      likedByMe: !post.likedByMe,
      likeCount: post.likedByMe ? post.likeCount - 1 : post.likeCount + 1,
    );
    setState(() => _post = optimistic);

    try {
      final api = ref.read(postsApiProvider);
      final result = post.likedByMe
          ? await api.unlike(post.id)
          : await api.like(post.id);
      if (mounted) {
        setState(
          () => _post = optimistic.copyWith(
            likedByMe: result.likedByMe,
            likeCount: result.likeCount,
          ),
        );
      }
    } on PostsApiException {
      if (mounted) setState(() => _post = post);
    }
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isPostingComment = true);
    try {
      final comment = await ref
          .read(postsApiProvider)
          .addComment(widget.postId, text);
      setState(() {
        _comments = [..._comments, comment];
        _commentController.clear();
        final post = _post;
        if (post != null) {
          _post = Post(
            id: post.id,
            imageUrl: post.imageUrl,
            caption: post.caption,
            createdAt: post.createdAt,
            author: post.author,
            likeCount: post.likeCount,
            commentCount: post.commentCount + 1,
            likedByMe: post.likedByMe,
          );
        }
      });
    } on PostsApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _isPostingComment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _post == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error ?? 'Post not found'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final post = _post!;

    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: CachedNetworkImage(
                  imageUrl: post.imageUrl,
                  fit: BoxFit.cover,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _toggleLike,
                      icon: Icon(
                        post.likedByMe
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: post.likedByMe ? Colors.red : null,
                      ),
                    ),
                    Text('${post.likeCount} likes'),
                  ],
                ),
              ),
              if (post.caption != null && post.caption!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: RichText(
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: '@${post.author.username} ',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: post.caption),
                      ],
                    ),
                  ),
                ),
              const Divider(),
              for (final comment in _comments)
                ListTile(
                  title: Text(
                    '@${comment.author.username}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(comment.text),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isPostingComment ? null : _submitComment,
                  icon: _isPostingComment
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
    );
  }
}
