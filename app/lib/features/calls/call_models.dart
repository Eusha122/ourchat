import '../posts/data/post_models.dart';

enum CallKind {
  audio,
  video;

  String get wireValue => name;

  String get label => this == CallKind.video ? 'Video call' : 'Voice call';

  static CallKind fromWire(String value) =>
      value == 'audio' ? CallKind.audio : CallKind.video;
}

class CallOffer {
  const CallOffer({
    required this.callId,
    required this.conversationId,
    required this.kind,
    required this.offerType,
    required this.offerSdp,
    required this.caller,
  });

  factory CallOffer.fromJson(Map<String, dynamic> json) => CallOffer(
    callId: json['callId'] as String,
    conversationId: json['conversationId'] as String,
    kind: CallKind.fromWire(json['kind'] as String),
    offerType: (json['offer'] as Map<String, dynamic>)['type'] as String,
    offerSdp: (json['offer'] as Map<String, dynamic>)['sdp'] as String,
    caller: PostAuthor.fromJson(json['caller'] as Map<String, dynamic>),
  );

  final String callId;
  final String conversationId;
  final CallKind kind;
  final String offerType;
  final String offerSdp;
  final PostAuthor caller;
}

class CallAnswer {
  const CallAnswer({
    required this.callId,
    required this.type,
    required this.sdp,
  });

  factory CallAnswer.fromJson(Map<String, dynamic> json) {
    final answer = json['answer'] as Map<String, dynamic>;
    return CallAnswer(
      callId: json['callId'] as String,
      type: answer['type'] as String,
      sdp: answer['sdp'] as String,
    );
  }

  final String callId;
  final String type;
  final String sdp;
}

class CallIceCandidate {
  const CallIceCandidate({
    required this.callId,
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
  });

  factory CallIceCandidate.fromJson(Map<String, dynamic> json) {
    final candidate = json['candidate'] as Map<String, dynamic>;
    return CallIceCandidate(
      callId: json['callId'] as String,
      candidate: candidate['candidate'] as String,
      sdpMid: candidate['sdpMid'] as String?,
      sdpMLineIndex: candidate['sdpMLineIndex'] as int?,
    );
  }

  final String callId;
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
}

class CallEndedEvent {
  const CallEndedEvent({required this.callId, required this.reason});

  factory CallEndedEvent.fromJson(Map<String, dynamic> json) => CallEndedEvent(
    callId: json['callId'] as String,
    reason: json['reason'] as String? ?? 'ended',
  );

  final String callId;
  final String reason;
}
