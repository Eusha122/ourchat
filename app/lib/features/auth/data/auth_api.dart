import 'package:dio/dio.dart';

import '../../../core/api_client.dart';
import 'auth_models.dart';

class AuthApiException implements Exception {
  AuthApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthApi {
  AuthApi()
    : _dio = Dio(
        BaseOptions(
          baseUrl: apiBaseUrl,
          // Authentication gates the splash route. Without explicit bounds,
          // an unreachable host can leave a restored session on the spinner
          // indefinitely instead of falling back to the sign-in screen.
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

  final Dio _dio;

  Future<AuthResult> register({
    required String username,
    required String email,
    required String password,
    String? displayName,
  }) async {
    return _handle(() async {
      final response = await _dio.post(
        '/auth/register',
        data: {
          'username': username,
          'email': email,
          'password': password,
          if (displayName != null && displayName.isNotEmpty)
            'displayName': displayName,
        },
      );
      return AuthResult.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<AuthResult> login({
    required String usernameOrEmail,
    required String password,
  }) async {
    return _handle(() async {
      final response = await _dio.post(
        '/auth/login',
        data: {'usernameOrEmail': usernameOrEmail, 'password': password},
      );
      return AuthResult.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<PublicUser> fetchMe(String accessToken) async {
    return _handle(() async {
      final response = await _dio.get(
        '/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      final data = response.data as Map<String, dynamic>;
      return PublicUser.fromJson(data['user'] as Map<String, dynamic>);
    });
  }

  Future<AuthTokensRefresh> refresh(String refreshToken) async {
    return _handle(() async {
      final response = await _dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = response.data as Map<String, dynamic>;
      return AuthTokensRefresh(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );
    });
  }

  Future<T> _handle<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) {
        final error = data['error'];
        if (error is String) throw AuthApiException(error);
        throw AuthApiException('Please check your input and try again.');
      }
      throw AuthApiException(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }
}

class AuthTokensRefresh {
  const AuthTokensRefresh({
    required this.accessToken,
    required this.refreshToken,
  });
  final String accessToken;
  final String refreshToken;
}
