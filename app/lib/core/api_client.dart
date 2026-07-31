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
  ApiClient({this._accessToken}) {
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
