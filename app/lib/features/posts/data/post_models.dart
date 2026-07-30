class PostAuthor {
  const PostAuthor({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
  });

  factory PostAuthor.fromJson(Map<String, dynamic> json) {
    return PostAuthor(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }

  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;
}

class Post {
  const Post({
    required this.id,
    required this.imageUrl,
    required this.caption,
    required this.createdAt,
    required this.author,
    required this.likeCount,
    required this.commentCount,
    required this.likedByMe,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as String,
      imageUrl: json['imageUrl'] as String,
      caption: json['caption'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      author: PostAuthor.fromJson(json['author'] as Map<String, dynamic>),
      likeCount: json['likeCount'] as int,
      commentCount: json['commentCount'] as int,
      likedByMe: json['likedByMe'] as bool,
    );
  }

  final String id;
  final String imageUrl;
  final String? caption;
  final DateTime createdAt;
  final PostAuthor author;
  final int likeCount;
  final int commentCount;
  final bool likedByMe;

  Post copyWith({int? likeCount, bool? likedByMe}) {
    return Post(
      id: id,
      imageUrl: imageUrl,
      caption: caption,
      createdAt: createdAt,
      author: author,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount,
      likedByMe: likedByMe ?? this.likedByMe,
    );
  }
}

class PostComment {
  const PostComment({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.author,
  });

  factory PostComment.fromJson(Map<String, dynamic> json) {
    return PostComment(
      id: json['id'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      author: PostAuthor.fromJson(json['author'] as Map<String, dynamic>),
    );
  }

  final String id;
  final String text;
  final DateTime createdAt;
  final PostAuthor author;
}

class FeedPage {
  const FeedPage({required this.posts, required this.nextCursor});

  factory FeedPage.fromJson(Map<String, dynamic> json) {
    return FeedPage(
      posts: (json['posts'] as List)
          .map((e) => Post.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: json['nextCursor'] as String?,
    );
  }

  final List<Post> posts;
  final String? nextCursor;
}

class CommentsPage {
  const CommentsPage({required this.comments, required this.nextCursor});

  factory CommentsPage.fromJson(Map<String, dynamic> json) {
    return CommentsPage(
      comments: (json['comments'] as List)
          .map((e) => PostComment.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: json['nextCursor'] as String?,
    );
  }

  final List<PostComment> comments;
  final String? nextCursor;
}

class LikeResult {
  const LikeResult({required this.likeCount, required this.likedByMe});

  factory LikeResult.fromJson(Map<String, dynamic> json) {
    return LikeResult(
      likeCount: json['likeCount'] as int,
      likedByMe: json['likedByMe'] as bool,
    );
  }

  final int likeCount;
  final bool likedByMe;
}
