import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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

enum ApkInstallerResult { installerOpened, permissionRequired }

class DownloadedUpdate {
  const DownloadedUpdate({required this.file});

  final File file;
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
  static const _installerChannel = MethodChannel('ourchat/apk_installer');

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

  /// Downloads the signed release to app-private cache storage. The download
  /// is written to a temporary file and only promoted when complete, so a
  /// cancelled or interrupted transfer can never be handed to Android's APK
  /// installer as if it were a valid update.
  Future<DownloadedUpdate> downloadApk(
    AppUpdateInfo update, {
    required void Function(int received, int total) onProgress,
  }) async {
    final cacheDirectory = await getTemporaryDirectory();
    final finalFile = File(
      '${cacheDirectory.path}${Platform.pathSeparator}ourchat-update-${update.availableVersionCode}.apk',
    );
    final partialFile = File('${finalFile.path}.part');
    if (await partialFile.exists()) await partialFile.delete();

    try {
      await _dio.downloadUri(
        update.downloadUrl,
        partialFile.path,
        deleteOnError: true,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(minutes: 5),
          headers: const {'Cache-Control': 'no-cache'},
        ),
        onReceiveProgress: onProgress,
      );
      final length = await partialFile.length();
      if (length < 1024 || !await _looksLikeZip(partialFile)) {
        throw const FormatException('The update file is invalid.');
      }
      if (await finalFile.exists()) await finalFile.delete();
      await partialFile.rename(finalFile.path);
      return DownloadedUpdate(file: finalFile);
    } on DioException catch (error) {
      throw StateError(
        error.type == DioExceptionType.cancel
            ? 'Update download cancelled.'
            : 'Could not download the update. Check your connection and try again.',
      );
    } finally {
      if (await partialFile.exists()) await partialFile.delete();
    }
  }

  Future<bool> _looksLikeZip(File file) async {
    final handle = await file.open();
    try {
      final header = await handle.read(4);
      return header.length == 4 &&
          header[0] == 0x50 &&
          header[1] == 0x4B &&
          (header[2] == 0x03 || header[2] == 0x05 || header[2] == 0x07) &&
          (header[3] == 0x04 || header[3] == 0x06 || header[3] == 0x08);
    } finally {
      await handle.close();
    }
  }

  /// Android validates that the downloaded APK is signed by this app's
  /// release key before allowing an update. The platform installer is the
  /// final authority; this method merely opens it without using a browser.
  Future<ApkInstallerResult> openInstaller(File apk) async {
    final result = await _installerChannel.invokeMethod<String>('installApk', {
      'path': apk.path,
    });
    return result == 'permission_required'
        ? ApkInstallerResult.permissionRequired
        : ApkInstallerResult.installerOpened;
  }
}
