import 'package:dio/dio.dart';

import 'post_models.dart';

class PostsApiException implements Exception {
  PostsApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class PostsApi {
  PostsApi(this._dio);

  final Dio _dio;

  Future<FeedPage> fetchFeed({String? cursor, int take = 20}) async {
    return _handle(() async {
      final response = await _dio.get(
        '/posts',
        queryParameters: {
          if (cursor != null) 'cursor': cursor,
          'take': take,
        },
      );
      return FeedPage.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<Post> fetchPost(String postId) async {
    return _handle(() async {
      final response = await _dio.get('/posts/$postId');
      final data = response.data as Map<String, dynamic>;
      return Post.fromJson(data['post'] as Map<String, dynamic>);
    });
  }

  Future<LikeResult> like(String postId) async {
    return _handle(() async {
      final response = await _dio.post('/posts/$postId/like');
      return LikeResult.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<LikeResult> unlike(String postId) async {
    return _handle(() async {
      final response = await _dio.delete('/posts/$postId/like');
      return LikeResult.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<CommentsPage> fetchComments(
    String postId, {
    String? cursor,
    int take = 20,
  }) async {
    return _handle(() async {
      final response = await _dio.get(
        '/posts/$postId/comments',
        queryParameters: {
          if (cursor != null) 'cursor': cursor,
          'take': take,
        },
      );
      return CommentsPage.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<PostComment> addComment(String postId, String text) async {
    return _handle(() async {
      final response = await _dio.post(
        '/posts/$postId/comments',
        data: {'text': text},
      );
      final data = response.data as Map<String, dynamic>;
      return PostComment.fromJson(data['comment'] as Map<String, dynamic>);
    });
  }

  Future<Post> createPost({required String imagePath, String? caption}) async {
    return _handle(() async {
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(imagePath),
        if (caption != null && caption.isNotEmpty) 'caption': caption,
      });
      final response = await _dio.post('/posts', data: formData);
      final data = response.data as Map<String, dynamic>;
      return Post.fromJson(data['post'] as Map<String, dynamic>);
    });
  }

  Future<T> _handle<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) {
        final error = data['error'];
        if (error is String) throw PostsApiException(error);
        throw PostsApiException('Please check your input and try again.');
      }
      throw PostsApiException(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }
}
