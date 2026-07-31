import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Dev-machine LAN IP, reachable from a physical Android device on the same
/// network (10.0.2.2 only works for the emulator, not a real phone).
/// Update this if the dev machine's IP changes.
const _devMachineLanIp = '192.168.0.100';

String get apiBaseUrl {
  if (!kIsWeb && Platform.isAndroid) {
    return 'http://$_devMachineLanIp:4000';
  }
  return 'http://localhost:4000';
}

class ApiClient {
  ApiClient({this._accessToken, this.onUnauthorized}) {
    dio = Dio(BaseOptions(baseUrl: apiBaseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_accessToken != null) {
            options.headers['Authorization'] = 'Bearer $_accessToken';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          // The 15-minute access token can expire mid-session (the app was
          // simply left open); refresh once and replay the failed request
          // instead of surfacing "Invalid or expired token" to the user.
          if (error.response?.statusCode == 401 && onUnauthorized != null) {
            final newToken = await onUnauthorized!();
            if (newToken != null) {
              _accessToken = newToken;
              final retryOptions = error.requestOptions;
              retryOptions.headers['Authorization'] = 'Bearer $newToken';
              try {
                handler.resolve(await dio.fetch(retryOptions));
                return;
              } on DioException catch (retryError) {
                handler.next(retryError);
                return;
              }
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  late final Dio dio;
  String? _accessToken;

  /// Invoked on a 401; should refresh the session and return the new access
  /// token, or null if the refresh token itself is no longer valid.
  final Future<String?> Function()? onUnauthorized;

  set accessToken(String? token) => _accessToken = token;
}
