import 'package:dio/dio.dart';

import '../../auth/data/auth_models.dart';

class UsersApiException implements Exception {
  UsersApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class UsersApi {
  UsersApi(this._dio);

  final Dio _dio;

  Future<PublicUser> updateProfile({String? displayName, String? bio}) async {
    return _handle(() async {
      final response = await _dio.patch(
        '/users/me',
        data: {
          if (displayName != null) 'displayName': displayName,
          if (bio != null) 'bio': bio,
        },
      );
      final data = response.data as Map<String, dynamic>;
      return PublicUser.fromJson(data['user'] as Map<String, dynamic>);
    });
  }

  Future<PublicUser> uploadAvatar(String filePath) async {
    return _handle(() async {
      final formData = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(filePath),
      });
      final response = await _dio.post('/users/me/avatar', data: formData);
      final data = response.data as Map<String, dynamic>;
      return PublicUser.fromJson(data['user'] as Map<String, dynamic>);
    });
  }

  Future<T> _handle<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) {
        final error = data['error'];
        if (error is String) throw UsersApiException(error);
        throw UsersApiException('Please check your input and try again.');
      }
      throw UsersApiException(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }
}
