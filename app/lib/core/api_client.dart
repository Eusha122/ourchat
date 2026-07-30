import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Android emulators reach the host machine's localhost via 10.0.2.2.
/// For a physical device on the same network, replace this with your
/// machine's LAN IP (e.g. http://192.168.1.23:4000).
String get apiBaseUrl {
  if (!kIsWeb && Platform.isAndroid) {
    return 'http://10.0.2.2:4000';
  }
  return 'http://localhost:4000';
}

class ApiClient {
  ApiClient({String? accessToken}) : _accessToken = accessToken {
    dio = Dio(BaseOptions(baseUrl: apiBaseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_accessToken != null) {
            options.headers['Authorization'] = 'Bearer $_accessToken';
          }
          handler.next(options);
        },
      ),
    );
  }

  late final Dio dio;
  String? _accessToken;

  set accessToken(String? token) => _accessToken = token;
}
