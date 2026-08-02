import 'package:dio/dio.dart';

import 'chat_models.dart';

class ConversationsApiException implements Exception {
  ConversationsApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ConversationsApi {
  ConversationsApi(this._dio);

  final Dio _dio;

  Future<Conversation> startConversation(String username) async {
    return _handle(() async {
      final response = await _dio.post(
        '/conversations',
        data: {'username': username},
      );
      final data = response.data as Map<String, dynamic>;
      return Conversation.fromJson(
        data['conversation'] as Map<String, dynamic>,
      );
    });
  }

  Future<List<Conversation>> fetchConversations() async {
    return _handle(() async {
      final response = await _dio.get('/conversations');
      final data = response.data as Map<String, dynamic>;
      final conversations = <Conversation>[];
      for (final entry in data['conversations'] as List) {
        try {
          conversations.add(
            Conversation.fromJson(entry as Map<String, dynamic>),
          );
        } catch (_) {
          // Skip an individual unparseable row rather than letting it throw
          // out of the whole request — one malformed conversation must never
          // leave the user staring at an empty chat list.
        }
      }
      return conversations;
    });
  }

  Future<Conversation> fetchConversation(String conversationId) async {
    return _handle(() async {
      final response = await _dio.get('/conversations/$conversationId');
      final data = response.data as Map<String, dynamic>;
      return Conversation.fromJson(
        data['conversation'] as Map<String, dynamic>,
      );
    });
  }

  Future<MessagesPage> fetchMessages(
    String conversationId, {
    String? cursor,
    int take = 30,
  }) async {
    return _handle(() async {
      final response = await _dio.get(
        '/conversations/$conversationId/messages',
        queryParameters: {'cursor': ?cursor, 'take': take},
      );
      return MessagesPage.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<ChatMessage> sendMessage(
    String conversationId,
    String text, {
    String? replyToId,
  }) async {
    return _handle(() async {
      final response = await _dio.post(
        '/conversations/$conversationId/messages',
        data: {
          'type': 'TEXT',
          'text': text,
          if (replyToId != null) 'replyToId': replyToId,
        },
      );
      final data = response.data as Map<String, dynamic>;
      return ChatMessage.fromJson(data['message'] as Map<String, dynamic>);
    });
  }

  /// Fetches short-lived TURN credentials plus public STUN fallback servers.
  /// The credentials are minted by the authenticated backend and never baked
  /// into the APK, allowing calls to relay across restrictive home/mobile NATs.
  Future<List<Map<String, dynamic>>> fetchCallIceServers() async {
    return _handle(() async {
      final response = await _dio.get('/conversations/call-ice-servers');
      final data = response.data as Map<String, dynamic>;
      final servers = data['iceServers'];
      if (servers is! List) return const [];
      return servers
          .whereType<Map>()
          .map((server) => Map<String, dynamic>.from(server))
          .toList(growable: false);
    });
  }

  Future<ChatMessage> sendLink(String conversationId, String linkUrl) async {
    return _handle(() async {
      final response = await _dio.post(
        '/conversations/$conversationId/messages',
        data: {'type': 'LINK', 'linkUrl': linkUrl},
      );
      final data = response.data as Map<String, dynamic>;
      return ChatMessage.fromJson(data['message'] as Map<String, dynamic>);
    });
  }

  /// Uploads an image or arbitrary file and sends it as a chat message in one
  /// call. [isImage] picks the message type (IMAGE vs FILE) the backend
  /// stores it under.
  Future<ChatMessage> sendAttachment(
    String conversationId, {
    required String filePath,
    required String fileName,
    required bool isImage,
    String? replyToId,
    bool isVoice = false,
    int? voiceDurationSeconds,
  }) async {
    return _handle(() async {
      final form = FormData.fromMap({
        'type': isImage ? 'IMAGE' : 'FILE',
        if (replyToId != null) 'replyToId': replyToId,
        if (isVoice) 'isVoice': 'true',
        if (voiceDurationSeconds != null)
          'voiceDurationSeconds': voiceDurationSeconds.toString(),
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });
      final response = await _dio.post(
        '/conversations/$conversationId/messages',
        data: form,
      );
      final data = response.data as Map<String, dynamic>;
      return ChatMessage.fromJson(data['message'] as Map<String, dynamic>);
    });
  }

  Future<void> markRead(String conversationId) async {
    return _handle(() async {
      await _dio.post('/conversations/$conversationId/read');
    });
  }

  Future<void> setPinned(String conversationId, bool pinned) async {
    return _handle(() async {
      await _dio.post(
        '/conversations/$conversationId/pin',
        data: {'pinned': pinned},
      );
    });
  }

  Future<void> setMuted(
    String conversationId, {
    bool? messages,
    bool? calls,
  }) async {
    return _handle(() async {
      await _dio.post(
        '/conversations/$conversationId/mute',
        data: {'messages': ?messages, 'calls': ?calls},
      );
    });
  }

  Future<void> deleteConversation(String conversationId) async {
    return _handle(() async {
      await _dio.delete('/conversations/$conversationId');
    });
  }

  Future<void> removeForMe(String conversationId, String messageId) async {
    return _handle(() async {
      await _dio.post(
        '/conversations/$conversationId/messages/$messageId/hide',
      );
    });
  }

  Future<ChatMessage> unsendMessage(
    String conversationId,
    String messageId,
  ) async {
    return _handle(() async {
      final response = await _dio.post(
        '/conversations/$conversationId/messages/$messageId/unsend',
      );
      final data = response.data as Map<String, dynamic>;
      return ChatMessage.fromJson(data['message'] as Map<String, dynamic>);
    });
  }

  Future<ChatMessage> reactToMessage(
    String conversationId,
    String messageId,
    String emoji,
  ) async {
    return _handle(() async {
      final response = await _dio.post(
        '/conversations/$conversationId/messages/$messageId/reactions',
        data: {'emoji': emoji},
      );
      final data = response.data as Map<String, dynamic>;
      return ChatMessage.fromJson(data['message'] as Map<String, dynamic>);
    });
  }

  Future<T> _handle<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) {
        final error = data['error'];
        if (error is String) throw ConversationsApiException(error);
        throw ConversationsApiException(
          'Please check your input and try again.',
        );
      }
      throw ConversationsApiException(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }
}
