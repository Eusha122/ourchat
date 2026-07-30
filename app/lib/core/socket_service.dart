import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../features/chat/data/chat_models.dart';
import 'api_client.dart';

class SocketService {
  SocketService({required this.accessToken});

  final String accessToken;
  io.Socket? _socket;

  final _messageController = StreamController<ChatMessage>.broadcast();
  final _conversationUpdateController =
      StreamController<ConversationUpdateEvent>.broadcast();
  final _typingController = StreamController<TypingEvent>.broadcast();

  Stream<ChatMessage> get onMessage => _messageController.stream;
  Stream<ConversationUpdateEvent> get onConversationUpdate =>
      _conversationUpdateController.stream;
  Stream<TypingEvent> get onTyping => _typingController.stream;

  void connect() {
    _socket = io.io(
      apiBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': accessToken})
          .build(),
    );

    _socket!.on('message:new', (data) {
      _messageController.add(
        ChatMessage.fromJson(Map<String, dynamic>.from(data as Map)),
      );
    });
    _socket!.on('conversation:updated', (data) {
      _conversationUpdateController.add(
        ConversationUpdateEvent.fromJson(
          Map<String, dynamic>.from(data as Map),
        ),
      );
    });
    _socket!.on('typing', (data) {
      _typingController.add(
        TypingEvent.fromJson(Map<String, dynamic>.from(data as Map)),
      );
    });
  }

  void joinConversation(String conversationId) =>
      _socket?.emit('conversation:join', conversationId);

  void leaveConversation(String conversationId) =>
      _socket?.emit('conversation:leave', conversationId);

  void sendTyping(String conversationId, bool isTyping) {
    _socket?.emit('typing', {
      'conversationId': conversationId,
      'isTyping': isTyping,
    });
  }

  void dispose() {
    _socket?.dispose();
    _messageController.close();
    _conversationUpdateController.close();
    _typingController.close();
  }
}
