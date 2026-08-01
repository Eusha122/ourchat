import 'package:dio/dio.dart';

import 'album_models.dart';

class AlbumsApiException implements Exception {
  AlbumsApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AlbumsApi {
  AlbumsApi(this._dio);

  final Dio _dio;

  Future<List<Album>> fetchAlbums() async {
    return _handle(() async {
      final response = await _dio.get('/albums');
      final data = response.data as Map<String, dynamic>;
      final albums = <Album>[];
      for (final entry in data['albums'] as List) {
        try {
          albums.add(Album.fromJson(entry as Map<String, dynamic>));
        } catch (_) {
          // One malformed row must never blank the whole gallery.
        }
      }
      return albums;
    });
  }

  Future<Album> createAlbum({
    required String username,
    required String name,
  }) async {
    return _handle(() async {
      final response = await _dio.post(
        '/albums',
        data: {'username': username, 'name': name},
      );
      final data = response.data as Map<String, dynamic>;
      return Album.fromJson(data['album'] as Map<String, dynamic>);
    });
  }

  Future<AlbumDetail> fetchAlbum(String albumId) async {
    return _handle(() async {
      final response = await _dio.get('/albums/$albumId');
      final data = response.data as Map<String, dynamic>;
      final items = <AlbumItem>[];
      for (final entry in data['items'] as List) {
        try {
          items.add(AlbumItem.fromJson(entry as Map<String, dynamic>));
        } catch (_) {
          // Skip an unreadable item rather than losing the whole vault.
        }
      }
      return AlbumDetail(
        album: Album.fromJson(data['album'] as Map<String, dynamic>),
        items: items,
      );
    });
  }

  Future<AlbumItem> uploadItem({
    required String albumId,
    required String filePath,
    required String fileName,
  }) async {
    return _handle(() async {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });
      final response = await _dio.post(
        '/albums/$albumId/items',
        data: form,
        // Videos can be large and slow on mobile data; the default timeout
        // would abort a perfectly healthy upload.
        options: Options(sendTimeout: const Duration(minutes: 5)),
      );
      final data = response.data as Map<String, dynamic>;
      return AlbumItem.fromJson(data['item'] as Map<String, dynamic>);
    });
  }

  Future<T> _handle<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) {
        final error = data['error'];
        if (error is String) throw AlbumsApiException(error);
        throw AlbumsApiException('Please check your input and try again.');
      }
      throw AlbumsApiException(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }
}
