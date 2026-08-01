import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../features/chat/data/chat_models.dart';
import '../features/calls/call_models.dart';
import 'api_client.dart';
import 'notification_service.dart';

class SocketService {
  SocketService({required this.accessToken, required this.currentUserId});

  final String accessToken;
  final String currentUserId;
  io.Socket? _socket;

  final _messageController = StreamController<ChatMessage>.broadcast();
  final _conversationUpdateController =
      StreamController<ConversationUpdateEvent>.broadcast();
  final _typingController = StreamController<TypingEvent>.broadcast();
  final _presenceController = StreamController<PresenceEvent>.broadcast();
  final _conversationReadController =
      StreamController<ConversationReadEvent>.broadcast();
  final _conversationDeletedController =
      StreamController<String>.broadcast();
  final _messageUpdateController = StreamController<ChatMessage>.broadcast();
  final _messageRemovedController =
      StreamController<MessageRemovedEvent>.broadcast();
  final _callOfferController = StreamController<CallOffer>.broadcast();
  final _callAnswerController = StreamController<CallAnswer>.broadcast();
  final _callIceController = StreamController<CallIceCandidate>.broadcast();
  final _callEndedController = StreamController<CallEndedEvent>.broadcast();
  final _callReadyController = StreamController<String>.broadcast();
  final _pendingIce = <String, List<CallIceCandidate>>{};

  Stream<ChatMessage> get onMessage => _messageController.stream;
  Stream<ConversationUpdateEvent> get onConversationUpdate =>
      _conversationUpdateController.stream;
  Stream<TypingEvent> get onTyping => _typingController.stream;
  Stream<PresenceEvent> get onPresence => _presenceController.stream;
  Stream<ConversationReadEvent> get onConversationRead =>
      _conversationReadController.stream;
  /// Emits the conversationId that was permanently deleted, by either side.
  Stream<String> get onConversationDeleted =>
      _conversationDeletedController.stream;
  Stream<ChatMessage> get onMessageUpdated => _messageUpdateController.stream;
  Stream<MessageRemovedEvent> get onMessageRemoved =>
      _messageRemovedController.stream;
  Stream<CallOffer> get onCallOffer => _callOfferController.stream;
  Stream<CallAnswer> get onCallAnswer => _callAnswerController.stream;
  Stream<CallIceCandidate> get onCallIce => _callIceController.stream;
  Stream<CallEndedEvent> get onCallEnded => _callEndedController.stream;
  Stream<String> get onCallReady => _callReadyController.stream;

  void connect() {
    _socket = io.io(
      apiBaseUrl,
      io.OptionBuilder().setTransports(['websocket']).setAuth({
        'token': accessToken,
      }).build(),
    );

    _socket!.on('message:new', (data) {
      final message = ChatMessage.fromJson(
        Map<String, dynamic>.from(data as Map),
      );
      _messageController.add(message);
      // Skip our own messages echoed back (e.g. when we have the
      // conversation open and just sent it ourselves).
      if (message.sender.id != currentUserId) {
        NotificationService().playMessageNotification();
      }
    });
    _socket!.on('conversation:updated', (data) {
      _conversationUpdateController.add(
        ConversationUpdateEvent.fromJson(
          Map<String, dynamic>.from(data as Map),
        ),
      );
    });
    _socket!.on('message:updated', (data) {
      _messageUpdateController.add(
        ChatMessage.fromJson(Map<String, dynamic>.from(data as Map)),
      );
    });
    _socket!.on('message:removed', (data) {
      _messageRemovedController.add(
        MessageRemovedEvent.fromJson(Map<String, dynamic>.from(data as Map)),
      );
    });
    _socket!.on('typing', (data) {
      _typingController.add(
        TypingEvent.fromJson(Map<String, dynamic>.from(data as Map)),
      );
    });
    _socket!.on('presence:update', (data) {
      _presenceController.add(
        PresenceEvent.fromJson(Map<String, dynamic>.from(data as Map)),
      );
    });
    _socket!.on('conversation:read', (data) {
      _conversationReadController.add(
        ConversationReadEvent.fromJson(Map<String, dynamic>.from(data as Map)),
      );
    });
    _socket!.on('conversation:deleted', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      final conversationId = map['conversationId'];
      if (conversationId is String) {
        _conversationDeletedController.add(conversationId);
      }
    });
    _socket!.on('call:offer', (data) {
      _callOfferController.add(
        CallOffer.fromJson(Map<String, dynamic>.from(data as Map)),
      );
    });
    _socket!.on('call:answer', (data) {
      _callAnswerController.add(
        CallAnswer.fromJson(Map<String, dynamic>.from(data as Map)),
      );
    });
    _socket!.on('call:ice', (data) {
      final candidate = CallIceCandidate.fromJson(
        Map<String, dynamic>.from(data as Map),
      );
      (_pendingIce[candidate.callId] ??= []).add(candidate);
      _callIceController.add(candidate);
    });
    _socket!.on('call:end', (data) {
      _callEndedController.add(
        CallEndedEvent.fromJson(Map<String, dynamic>.from(data as Map)),
      );
    });
    _socket!.on('call:ready', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      final callId = map['callId'];
      if (callId is String) _callReadyController.add(callId);
    });
  }

  void joinConversation(String conversationId) =>
      _socket?.emit('conversation:join', conversationId);

  void leaveConversation(String conversationId) =>
      _socket?.emit('conversation:leave', conversationId);

  void queryPresence(String userId) => _socket?.emit('presence:query', userId);

  void sendTyping(String conversationId, bool isTyping) {
    _socket?.emit('typing', {
      'conversationId': conversationId,
      'isTyping': isTyping,
    });
  }

  void sendCallOffer({
    required String callId,
    required String conversationId,
    required CallKind kind,
    required String type,
    required String sdp,
  }) => _socket?.emit('call:offer', {
    'callId': callId,
    'conversationId': conversationId,
    'kind': kind.wireValue,
    'offer': {'type': type, 'sdp': sdp},
  });

  void sendCallAnswer({
    required String callId,
    required String type,
    required String sdp,
  }) => _socket?.emit('call:answer', {
    'callId': callId,
    'answer': {'type': type, 'sdp': sdp},
  });

  void sendCallIce({
    required String callId,
    required String candidate,
    required String? sdpMid,
    required int? sdpMLineIndex,
  }) => _socket?.emit('call:ice', {
    'callId': callId,
    'candidate': {
      'candidate': candidate,
      'sdpMid': sdpMid,
      'sdpMLineIndex': sdpMLineIndex,
    },
  });

  void endCall(String callId, {String reason = 'ended'}) {
    _pendingIce.remove(callId);
    _socket?.emit('call:end', {'callId': callId, 'reason': reason});
  }

  List<CallIceCandidate> takePendingIce(String callId) =>
      _pendingIce.remove(callId) ?? const [];

  void dispose() {
    _socket?.dispose();
    _messageController.close();
    _conversationUpdateController.close();
    _typingController.close();
    _presenceController.close();
    _conversationReadController.close();
    _conversationDeletedController.close();
    _messageUpdateController.close();
    _messageRemovedController.close();
    _callOfferController.close();
    _callAnswerController.close();
    _callIceController.close();
    _callEndedController.close();
    _callReadyController.close();
  }
}
