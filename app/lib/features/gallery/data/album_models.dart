import '../../posts/data/post_models.dart' show PostAuthor;

class Album {
  const Album({
    required this.id,
    required this.name,
    required this.otherMember,
    required this.itemCount,
    required this.coverUrl,
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    final other = json['otherMember'];
    return Album(
      id: json['id'] as String,
      name: json['name'] as String,
      otherMember: other == null
          ? null
          : PostAuthor.fromJson(other as Map<String, dynamic>),
      itemCount: json['itemCount'] as int? ?? 0,
      coverUrl: json['coverUrl'] as String?,
    );
  }

  final String id;
  final String name;

  /// The person this vault is shared with. Null only if their account is
  /// gone, which the UI renders as a plain album rather than breaking.
  final PostAuthor? otherMember;
  final int itemCount;
  final String? coverUrl;
}

enum AlbumItemType { image, video }

class AlbumItem {
  const AlbumItem({
    required this.id,
    required this.url,
    required this.thumbnailUrl,
    required this.type,
    required this.uploader,
    required this.createdAt,
  });

  factory AlbumItem.fromJson(Map<String, dynamic> json) {
    return AlbumItem(
      id: json['id'] as String,
      url: json['url'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      type: switch (json['type']) {
        'VIDEO' => AlbumItemType.video,
        _ => AlbumItemType.image,
      },
      uploader: PostAuthor.fromJson(json['uploader'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  final String id;
  final String url;
  final String? thumbnailUrl;
  final AlbumItemType type;
  final PostAuthor uploader;
  final DateTime createdAt;

  /// Grid cells prefer the cheap derived crop when the backend produced one.
  String get displayUrl => thumbnailUrl ?? url;
}

class AlbumDetail {
  const AlbumDetail({required this.album, required this.items});

  final Album album;
  final List<AlbumItem> items;
}
