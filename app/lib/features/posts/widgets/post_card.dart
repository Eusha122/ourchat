import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/post_models.dart';

class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onToggleLike,
    required this.onOpen,
    required this.onOpenAuthor,
  });

  final Post post;
  final VoidCallback onToggleLike;
  final VoidCallback onOpen;
  final VoidCallback onOpenAuthor;

  @override
  Widget build(BuildContext context) {
    final author = post.author;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          onTap: onOpenAuthor,
          leading: CircleAvatar(
            backgroundImage: author.avatarUrl != null
                ? CachedNetworkImageProvider(author.avatarUrl!)
                : null,
            child: author.avatarUrl == null
                ? const Icon(Icons.person)
                : null,
          ),
          title: Text(
            author.displayName?.isNotEmpty == true
                ? author.displayName!
                : '@${author.username}',
          ),
        ),
        GestureDetector(
          onTap: onOpen,
          child: AspectRatio(
            aspectRatio: 1,
            child: CachedNetworkImage(
              imageUrl: post.imageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) =>
                  const Center(child: CircularProgressIndicator()),
              errorWidget: (context, url, error) =>
                  const Center(child: Icon(Icons.broken_image)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: onToggleLike,
                icon: Icon(
                  post.likedByMe ? Icons.favorite : Icons.favorite_border,
                  color: post.likedByMe ? Colors.red : null,
                ),
              ),
              Text('${post.likeCount}'),
              const SizedBox(width: 16),
              IconButton(
                onPressed: onOpen,
                icon: const Icon(Icons.mode_comment_outlined),
              ),
              Text('${post.commentCount}'),
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
                    text: '@${author.username} ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: post.caption),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
