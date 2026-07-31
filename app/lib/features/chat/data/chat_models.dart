import '../../posts/data/post_models.dart';

enum MessageType {
  text,
  link,
  image,
  file,
  call;

  static MessageType fromJson(String value) => switch (value) {
    'LINK' => MessageType.link,
    'IMAGE' => MessageType.image,
    'FILE' => MessageType.file,
    'CALL' => MessageType.call,
    _ => MessageType.text,
  };
}

class LastMessage {
  const LastMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.createdAt,
  });

  factory LastMessage.fromJson(Map<String, dynamic> json) {
    return LastMessage(
      id: json['id'] as String,
      text: json['text'] as String?,
      senderId: json['senderId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  final String id;
  final String? text;
  final String senderId;
  final DateTime createdAt;

  /// A short, always-non-null preview for chat-list rows.
  String get preview => text ?? '🔗 Link';
}

class Conversation {
  const Conversation({
    required this.id,
    required this.otherParticipant,
    required this.lastMessage,
    required this.unreadCount,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      otherParticipant: PostAuthor.fromJson(
        json['otherParticipant'] as Map<String, dynamic>,
      ),
      lastMessage: json['lastMessage'] != null
          ? LastMessage.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
      // POST /conversations (start/lookup) only returns id + otherParticipant;
      // unreadCount/lastMessage are absent there and only populated by the
      // GET /conversations list endpoint.
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }

  final String id;
  final PostAuthor otherParticipant;
  final LastMessage? lastMessage;
  final int unreadCount;

  Conversation copyWith({LastMessage? lastMessage, int? unreadCount}) {
    return Conversation(
      id: id,
      otherParticipant: otherParticipant,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.type,
    required this.text,
    required this.linkUrl,
    required this.linkTitle,
    required this.linkImageUrl,
    required this.fileSize,
    required this.callKind,
    required this.callStatus,
    required this.callDurationSeconds,
    required this.isUnsent,
    required this.reactions,
    required this.createdAt,
    required this.sender,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String,
      type: MessageType.fromJson(json['type'] as String),
      text: json['text'] as String?,
      linkUrl: json['linkUrl'] as String?,
      linkTitle: json['linkTitle'] as String?,
      linkImageUrl: json['linkImageUrl'] as String?,
      fileSize: json['fileSize'] as int?,
      callKind: json['callKind'] as String?,
      callStatus: json['callStatus'] as String?,
      callDurationSeconds: json['callDurationSeconds'] as int?,
      isUnsent: json['isUnsent'] as bool? ?? false,
      reactions: (json['reactions'] as List? ?? const [])
          .map((item) => MessageReaction.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      createdAt: DateTime.parse(json['createdAt'] as String),
      sender: PostAuthor.fromJson(json['sender'] as Map<String, dynamic>),
    );
  }

  final String id;
  final String conversationId;
  final MessageType type;
  final String? text;
  final String? linkUrl;
  final String? linkTitle;
  final String? linkImageUrl;
  final int? fileSize;
  final String? callKind;
  final String? callStatus;
  final int? callDurationSeconds;
  final bool isUnsent;
  final List<MessageReaction> reactions;
  final DateTime createdAt;
  final PostAuthor sender;

  ChatMessage copyWith({
    MessageType? type,
    String? text,
    String? linkUrl,
    String? linkTitle,
    String? linkImageUrl,
    int? fileSize,
    String? callKind,
    String? callStatus,
    int? callDurationSeconds,
    bool? isUnsent,
    List<MessageReaction>? reactions,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      type: type ?? this.type,
      text: text ?? this.text,
      linkUrl: linkUrl ?? this.linkUrl,
      linkTitle: linkTitle ?? this.linkTitle,
      linkImageUrl: linkImageUrl ?? this.linkImageUrl,
      fileSize: fileSize ?? this.fileSize,
      callKind: callKind ?? this.callKind,
      callStatus: callStatus ?? this.callStatus,
      callDurationSeconds: callDurationSeconds ?? this.callDurationSeconds,
      isUnsent: isUnsent ?? this.isUnsent,
      reactions: reactions ?? this.reactions,
      createdAt: createdAt,
      sender: sender,
    );
  }
}

class MessageReaction {
  const MessageReaction({required this.userId, required this.emoji});

  factory MessageReaction.fromJson(Map<String, dynamic> json) =>
      MessageReaction(
        userId: json['userId'] as String,
        emoji: json['emoji'] as String,
      );

  final String userId;
  final String emoji;
}

class MessageRemovedEvent {
  const MessageRemovedEvent({
    required this.conversationId,
    required this.messageId,
  });

  factory MessageRemovedEvent.fromJson(Map<String, dynamic> json) =>
      MessageRemovedEvent(
        conversationId: json['conversationId'] as String,
        messageId: json['messageId'] as String,
      );

  final String conversationId;
  final String messageId;
}

class MessagesPage {
  const MessagesPage({required this.messages, required this.nextCursor});

  factory MessagesPage.fromJson(Map<String, dynamic> json) {
    return MessagesPage(
      messages: (json['messages'] as List)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: json['nextCursor'] as String?,
    );
  }

  final List<ChatMessage> messages;
  final String? nextCursor;
}

class ConversationUpdateEvent {
  const ConversationUpdateEvent({
    required this.conversationId,
    required this.lastMessage,
  });

  factory ConversationUpdateEvent.fromJson(Map<String, dynamic> json) {
    return ConversationUpdateEvent(
      conversationId: json['conversationId'] as String,
      lastMessage: LastMessage.fromJson(
        json['lastMessage'] as Map<String, dynamic>,
      ),
    );
  }

  final String conversationId;
  final LastMessage lastMessage;
}

class TypingEvent {
  const TypingEvent({required this.userId, required this.isTyping});

  factory TypingEvent.fromJson(Map<String, dynamic> json) {
    return TypingEvent(
      userId: json['userId'] as String,
      isTyping: json['isTyping'] as bool,
    );
  }

  final String userId;
  final bool isTyping;
}

class PresenceEvent {
  const PresenceEvent({required this.userId, required this.online});

  factory PresenceEvent.fromJson(Map<String, dynamic> json) {
    return PresenceEvent(
      userId: json['userId'] as String,
      online: json['online'] as bool,
    );
  }

  final String userId;
  final bool online;
}
