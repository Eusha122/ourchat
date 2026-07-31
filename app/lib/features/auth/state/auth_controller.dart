import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/token_storage.dart';
import '../data/auth_api.dart';
import '../data/auth_models.dart';
import 'auth_state.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
final authApiProvider = Provider<AuthApi>((ref) => AuthApi());

class AuthController extends AsyncNotifier<AuthState> {
  Future<String?>? _refreshInFlight;

  @override
  Future<AuthState> build() async {
    final storage = ref.read(tokenStorageProvider);
    final tokens = await storage.readTokens();
    if (tokens == null) return const AuthState.unauthenticated();

    final api = ref.read(authApiProvider);
    try {
      final user = await api.fetchMe(tokens.accessToken);
      return AuthState.authenticated(
        user: user,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
    } on AuthApiException {
      try {
        final refreshed = await api.refresh(tokens.refreshToken);
        final user = await api.fetchMe(refreshed.accessToken);
        await storage.saveTokens(
          AuthTokens(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
          ),
        );
        return AuthState.authenticated(
          user: user,
          accessToken: refreshed.accessToken,
          refreshToken: refreshed.refreshToken,
        );
      } catch (_) {
        await storage.clear();
        return const AuthState.unauthenticated();
      }
    }
  }

  Future<void> login({
    required String usernameOrEmail,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(authApiProvider);
      final result = await api.login(
        usernameOrEmail: usernameOrEmail,
        password: password,
      );
      await ref
          .read(tokenStorageProvider)
          .saveTokens(
            AuthTokens(
              accessToken: result.accessToken,
              refreshToken: result.refreshToken,
            ),
          );
      return AuthState.authenticated(
        user: result.user,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
    });
  }

  Future<void> register({
    required String username,
    required String email,
    required String password,
    String? displayName,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(authApiProvider);
      final result = await api.register(
        username: username,
        email: email,
        password: password,
        displayName: displayName,
      );
      await ref
          .read(tokenStorageProvider)
          .saveTokens(
            AuthTokens(
              accessToken: result.accessToken,
              refreshToken: result.refreshToken,
            ),
          );
      return AuthState.authenticated(
        user: result.user,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
    });
  }

  Future<void> logout() async {
    await ref.read(tokenStorageProvider).clear();
    state = const AsyncData(AuthState.unauthenticated());
  }

  /// Called by [ApiClient] when a request comes back 401 mid-session (the
  /// 15-minute access token expired while the app stayed open — `build()`
  /// only refreshes once, at startup). Concurrent 401s share one in-flight
  /// refresh instead of each firing their own. Returns the new access token
  /// to retry the failed request with, or null if the refresh token itself
  /// is no longer valid (in which case the user is logged out).
  Future<String?> refreshAccessToken() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<String?> _doRefresh() async {
    final current = state.value;
    if (current == null || !current.isAuthenticated) return null;

    try {
      final api = ref.read(authApiProvider);
      final refreshed = await api.refresh(current.refreshToken!);
      await ref
          .read(tokenStorageProvider)
          .saveTokens(
            AuthTokens(
              accessToken: refreshed.accessToken,
              refreshToken: refreshed.refreshToken,
            ),
          );
      state = AsyncData(
        AuthState.authenticated(
          user: current.user!,
          accessToken: refreshed.accessToken,
          refreshToken: refreshed.refreshToken,
        ),
      );
      return refreshed.accessToken;
    } catch (_) {
      await ref.read(tokenStorageProvider).clear();
      state = const AsyncData(AuthState.unauthenticated());
      return null;
    }
  }

  /// Patches the cached user (e.g. after a profile/avatar update) without
  /// re-authenticating.
  void updateUser(PublicUser user) {
    final current = state.value;
    if (current == null || !current.isAuthenticated) return;
    state = AsyncData(
      AuthState.authenticated(
        user: user,
        accessToken: current.accessToken!,
        refreshToken: current.refreshToken!,
      ),
    );
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
