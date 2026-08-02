import 'dart:async';
import 'dart:convert';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../features/chat/data/chat_models.dart';
import '../features/calls/call_models.dart';
import 'api_client.dart';

class SocketService {
  SocketService({
    required this.accessToken,
    required this.currentUserId,
    required this.refreshAccessToken,
  });

  final String accessToken;
  final String currentUserId;
  final Future<String?> Function() refreshAccessToken;
  io.Socket? _socket;
  Timer? _proactiveRefreshTimer;
  Future<void>? _refreshInFlight;
  bool _disposed = false;

  final _messageController = StreamController<ChatMessage>.broadcast();
  final _conversationUpdateController =
      StreamController<ConversationUpdateEvent>.broadcast();
  final _typingController = StreamController<TypingEvent>.broadcast();
  final _presenceController = StreamController<PresenceEvent>.broadcast();
  final _conversationReadController =
      StreamController<ConversationReadEvent>.broadcast();
  final _conversationDeletedController = StreamController<String>.broadcast();
  final _messageUpdateController = StreamController<ChatMessage>.broadcast();
  final _messageRemovedController =
      StreamController<MessageRemovedEvent>.broadcast();
  final _callOfferController = StreamController<CallOffer>.broadcast();
  final _callAnswerController = StreamController<CallAnswer>.broadcast();
  final _callIceController = StreamController<CallIceCandidate>.broadcast();
  final _callEndedController = StreamController<CallEndedEvent>.broadcast();
  final _callReadyController = StreamController<String>.broadcast();
  final _pendingIce = <String, List<CallIceCandidate>>{};

  // Kept in sync by whoever last fetched/edited the conversation list (see
  // ChatsScreen), since this plain Dart class has no Riverpod access of its
  // own to read that state directly.
  Set<String> _mutedMessageConversations = const {};
  Set<String> _mutedCallConversations = const {};

  void setMutedConversations({
    required Set<String> messages,
    required Set<String> calls,
  }) {
    _mutedMessageConversations = messages;
    _mutedCallConversations = calls;
  }

  bool isMessageMuted(String conversationId) =>
      _mutedMessageConversations.contains(conversationId);
  bool isCallMuted(String conversationId) =>
      _mutedCallConversations.contains(conversationId);
  bool get isConnected => _socket?.connected == true;

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
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableForceNew()
          .enableReconnection()
          .setReconnectionAttempts(1000000)
          .setReconnectionDelay(800)
          .setReconnectionDelayMax(5000)
          .setRandomizationFactor(0.25)
          .setTimeout(10000)
          .setAuth({'token': accessToken})
          .build(),
    );
    _scheduleProactiveRefresh();

    _socket!.onConnectError((error) {
      if (_isAuthenticationFailure(error)) {
        unawaited(_refreshForSocket());
      }
    });
    _socket!.onReconnectFailed((_) => unawaited(_refreshForSocket()));

    _socket!.on('message:new', (data) {
      final message = ChatMessage.fromJson(
        Map<String, dynamic>.from(data as Map),
      );
      _messageController.add(message);
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

  /// Reconnect immediately when the app returns to foreground. The client
  /// also retains its normal exponential reconnect loop while the network is
  /// briefly unavailable.
  void reconnect() {
    if (_disposed || _socket?.connected == true) return;
    _socket?.connect();
  }

  /// A call offer/answer must not be emitted into an expired or reconnecting
  /// socket buffer: signalling has a short lifetime and an old buffered offer
  /// can otherwise arrive after the caller has already given up. This bounded
  /// wait keeps call setup fast while giving normal network recovery time.
  Future<bool> ensureConnected({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (_disposed) return false;
    reconnect();
    final deadline = DateTime.now().add(timeout);
    while (!_disposed && DateTime.now().isBefore(deadline)) {
      if (isConnected) return true;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return isConnected;
  }

  void _scheduleProactiveRefresh() {
    final expiresAt = _jwtExpiry(accessToken);
    // A malformed/non-JWT access token will still be recovered by the
    // connect_error handler. Valid tokens refresh one minute before expiry.
    if (expiresAt == null) return;
    final delay = expiresAt
        .subtract(const Duration(minutes: 1))
        .difference(DateTime.now());
    _proactiveRefreshTimer = Timer(
      delay.isNegative ? const Duration(seconds: 1) : delay,
      () => unawaited(_refreshForSocket()),
    );
  }

  DateTime? _jwtExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final expiry = payload is Map ? payload['exp'] : null;
      if (expiry is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(expiry.toInt() * 1000);
    } catch (_) {
      return null;
    }
  }

  bool _isAuthenticationFailure(dynamic error) {
    final message = error is Map
        ? error['message']?.toString().toLowerCase() ?? ''
        : error.toString().toLowerCase();
    return message.contains('auth') ||
        message.contains('token') ||
        message.contains('expired') ||
        message.contains('invalid');
  }

  Future<void> _refreshForSocket() {
    return _refreshInFlight ??= _refreshForSocketImpl().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<void> _refreshForSocketImpl() async {
    if (_disposed) return;
    // Updating AuthController rebuilds socketServiceProvider with the fresh
    // token and disposes this stale socket before it can miss more events.
    await refreshAccessToken();
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
    _disposed = true;
    _proactiveRefreshTimer?.cancel();
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
