class PublicUser {
  const PublicUser({
    required this.id,
    required this.username,
    required this.email,
    this.displayName,
    this.bio,
    this.avatarUrl,
  });

  factory PublicUser.fromJson(Map<String, dynamic> json) {
    return PublicUser(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String?,
      bio: json['bio'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }

  final String id;
  final String username;
  final String email;
  final String? displayName;
  final String? bio;
  final String? avatarUrl;
}

class AuthResult {
  const AuthResult({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      user: PublicUser.fromJson(json['user'] as Map<String, dynamic>),
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
    );
  }

  final PublicUser user;
  final String accessToken;
  final String refreshToken;
}
