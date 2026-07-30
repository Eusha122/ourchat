import '../data/auth_models.dart';

enum AuthStatus { authenticated, unauthenticated }

class AuthState {
  const AuthState._({
    required this.status,
    this.user,
    this.accessToken,
    this.refreshToken,
  });

  const AuthState.unauthenticated() : this._(status: AuthStatus.unauthenticated);

  AuthState.authenticated({
    required PublicUser user,
    required String accessToken,
    required String refreshToken,
  }) : this._(
         status: AuthStatus.authenticated,
         user: user,
         accessToken: accessToken,
         refreshToken: refreshToken,
       );

  final AuthStatus status;
  final PublicUser? user;
  final String? accessToken;
  final String? refreshToken;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}
