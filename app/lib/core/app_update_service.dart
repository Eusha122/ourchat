import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_client.dart';

/// A verified update manifest supplied by the app backend.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersionCode,
    required this.currentVersionName,
    required this.availableVersionCode,
    required this.downloadUrl,
    this.releaseNotes,
  });

  final int currentVersionCode;
  final String currentVersionName;
  final int availableVersionCode;
  final Uri downloadUrl;
  final String? releaseNotes;
}

/// Reads the unsigned public release manifest. Network or malformed-manifest
/// failures are intentionally silent: an update check must never block launch.
class AppUpdateService {
  AppUpdateService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: apiBaseUrl,
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
            ),
          );

  final Dio _dio;

  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final package = await PackageInfo.fromPlatform();
      final currentVersionCode = int.tryParse(package.buildNumber) ?? 0;
      final response = await _dio.get<Map<String, dynamic>>('/app-version');
      final manifest = response.data;
      if (manifest == null) return null;

      final availableVersionCode = switch (manifest['versionCode']) {
        int value => value,
        num value => value.toInt(),
        String value => int.tryParse(value),
        _ => null,
      };
      final rawDownloadUrl = manifest['downloadUrl'];
      final downloadUrl = rawDownloadUrl is String
          ? Uri.tryParse(rawDownloadUrl)
          : null;

      if (availableVersionCode == null ||
          availableVersionCode <= currentVersionCode ||
          downloadUrl == null ||
          !downloadUrl.hasScheme ||
          downloadUrl.scheme != 'https') {
        return null;
      }

      final rawNotes = manifest['releaseNotes'];
      return AppUpdateInfo(
        currentVersionCode: currentVersionCode,
        currentVersionName: package.version,
        availableVersionCode: availableVersionCode,
        downloadUrl: downloadUrl,
        releaseNotes: rawNotes is String && rawNotes.trim().isNotEmpty
            ? rawNotes.trim()
            : null,
      );
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
