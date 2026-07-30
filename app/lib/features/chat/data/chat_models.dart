import '../../posts/data/post_models.dart';

enum MessageType {
  text,
  link;

  static MessageType fromJson(String value) =>
      value == 'LINK' ? MessageType.link : MessageType.text;
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
  final DateTime createdAt;
  final PostAuthor sender;
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
