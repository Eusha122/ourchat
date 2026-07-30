import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/token_storage.dart';
import '../data/auth_api.dart';
import 'auth_state.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
final authApiProvider = Provider<AuthApi>((ref) => AuthApi());

class AuthController extends AsyncNotifier<AuthState> {
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
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
