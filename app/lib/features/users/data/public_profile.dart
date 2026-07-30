class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.username,
    this.displayName,
    this.bio,
    this.avatarUrl,
    required this.createdAt,
  });

  factory PublicProfile.fromJson(Map<String, dynamic> json) {
    return PublicProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String?,
      bio: json['bio'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  final String id;
  final String username;
  final String? displayName;
  final String? bio;
  final String? avatarUrl;
  final DateTime createdAt;
}
