import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/socket_service.dart';
import '../../core/call_ringtone_service.dart';
import '../../core/notification_service.dart';
import '../chat/state/chat_providers.dart';
import '../posts/data/post_models.dart';
import 'call_models.dart';

const _violet = Color(0xFF5D4EF5);
const _deepViolet = Color(0xFF29205D);

class CallSessionScreen extends ConsumerStatefulWidget {
  const CallSessionScreen.outgoing({
    super.key,
    required this.conversationId,
    required this.otherParticipant,
    required this.kind,
  }) : offer = null;

  CallSessionScreen.incoming({super.key, required CallOffer offer})
    : offer = offer,
      conversationId = offer.conversationId,
      otherParticipant = offer.caller,
      kind = offer.kind;

  final String conversationId;
  final PostAuthor otherParticipant;
  final CallKind kind;
  final CallOffer? offer;

  bool get isIncoming => offer != null;

  @override
  ConsumerState<CallSessionScreen> createState() => _CallSessionScreenState();
}

class _CallSessionScreenState extends ConsumerState<CallSessionScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  final _random = Random.secure();
  final _queuedCandidates = <CallIceCandidate>[];
  final _outgoingIce = <RTCIceCandidate>[];

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  StreamSubscription<CallAnswer>? _answerSub;
  StreamSubscription<CallIceCandidate>? _iceSub;
  StreamSubscription<CallEndedEvent>? _endSub;
  StreamSubscription<String>? _readySub;
  StreamSubscription<CallNotificationAction>? _notificationActionSub;
  Timer? _durationTimer;
  String? _callId;
  bool _remoteDescriptionSet = false;
  bool _offerReady = false;
  bool _muted = false;
  bool _cameraEnabled = true;
  bool _speakerOn = true;
  bool _connected = false;
  bool _terminal = false;
  bool _starting = false;
  int _seconds = 0;
  String? _error;

  SocketService? get _socket => ref.read(socketServiceProvider);

  @override
  void initState() {
    super.initState();
    _notificationActionSub = NotificationService().onCallAction.listen((
      action,
    ) {
      final callId = _callId ?? widget.offer?.callId;
      if (!widget.isIncoming || callId != action.callId) return;
      if (action.actionId == NotificationService.acceptCallAction) {
        _acceptIncoming();
      } else if (action.actionId == NotificationService.declineCallAction) {
        _endCall(reason: 'declined');
      }
    });
    _boot();
  }

  Future<void> _boot() async {
    await _initializeRenderers();
    if (!mounted) return;
    _listenForSignals();
    if (!widget.isIncoming) {
      await _startOutgoing();
    }
  }

  Future<void> _initializeRenderers() async {
    await Future.wait([
      _localRenderer.initialize(),
      _remoteRenderer.initialize(),
    ]);
  }

  void _listenForSignals() {
    final socket = _socket;
    if (socket == null) return;
    _answerSub = socket.onCallAnswer.listen((answer) {
      if (answer.callId == _callId) _handleAnswer(answer);
    });
    _iceSub = socket.onCallIce.listen((candidate) {
      if (candidate.callId == _callId) _handleIceCandidate(candidate);
    });
    _endSub = socket.onCallEnded.listen((event) {
      if (event.callId == _callId) _handleRemoteEnd(event.reason);
    });
    _readySub = socket.onCallReady.listen((callId) {
      if (callId != _callId) return;
      _offerReady = true;
      _flushOutgoingIce();
    });
  }

  String _newCallId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 32).toRadixString(36)}';

  Future<void> _startOutgoing() async {
    _callId = _newCallId();
    setState(() => _starting = true);
    CallRingtoneService.instance.playOutgoing();
    try {
      await _prepareConnection();
      final peerConnection = _peerConnection!;
      final offer = await peerConnection.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.kind == CallKind.video,
      });
      await peerConnection.setLocalDescription(offer);
      final socket = _socket;
      if (socket == null || offer.sdp == null || offer.type == null) {
        throw StateError('Connection unavailable');
      }
      socket.sendCallOffer(
        callId: _callId!,
        conversationId: widget.conversationId,
        kind: widget.kind,
        type: offer.type!,
        sdp: offer.sdp!,
      );
    } catch (error) {
      if (mounted) setState(() => _error = _mediaError(error));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _acceptIncoming() async {
    if (_starting || _terminal) return;
    _callId = widget.offer!.callId;
    await CallRingtoneService.instance.stop();
    await NotificationService().dismissIncomingCall(_callId!);
    setState(() => _starting = true);
    try {
      await _prepareConnection();
      final peerConnection = _peerConnection!;
      await peerConnection.setRemoteDescription(
        RTCSessionDescription(widget.offer!.offerSdp, widget.offer!.offerType),
      );
      _remoteDescriptionSet = true;
      await _flushCandidates();
      final answer = await peerConnection.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.kind == CallKind.video,
      });
      await peerConnection.setLocalDescription(answer);
      final socket = _socket;
      if (socket == null || answer.sdp == null || answer.type == null) {
        throw StateError('Connection unavailable');
      }
      socket.sendCallAnswer(
        callId: _callId!,
        type: answer.type!,
        sdp: answer.sdp!,
      );
      _setConnected();
    } catch (error) {
      if (mounted) setState(() => _error = _mediaError(error));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _prepareConnection() async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.kind == CallKind.video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    });
    _localStream = stream;
    if (widget.kind == CallKind.video) _localRenderer.srcObject = stream;

    final peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    });
    _peerConnection = peerConnection;
    for (final track in stream.getTracks()) {
      await peerConnection.addTrack(track, stream);
    }
    peerConnection.onTrack = (event) {
      if (event.streams.isEmpty) return;
      _remoteRenderer.srcObject = event.streams.first;
      if (mounted) setState(() {});
      _setConnected();
    };
    peerConnection.onIceCandidate = (candidate) {
      final callId = _callId;
      if (callId == null || candidate.candidate == null) return;
      if (!widget.isIncoming && !_offerReady) {
        _outgoingIce.add(candidate);
        return;
      }
      _socket?.sendCallIce(
        callId: callId,
        candidate: candidate.candidate!,
        sdpMid: candidate.sdpMid,
        sdpMLineIndex: candidate.sdpMLineIndex,
      );
    };
    peerConnection.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setConnected();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _handleRemoteEnd('Connection lost');
      }
    };
  }

  void _flushOutgoingIce() {
    final callId = _callId;
    if (callId == null) return;
    while (_outgoingIce.isNotEmpty) {
      final candidate = _outgoingIce.removeAt(0);
      if (candidate.candidate == null) continue;
      _socket?.sendCallIce(
        callId: callId,
        candidate: candidate.candidate!,
        sdpMid: candidate.sdpMid,
        sdpMLineIndex: candidate.sdpMLineIndex,
      );
    }
  }

  Future<void> _handleAnswer(CallAnswer answer) async {
    final peerConnection = _peerConnection;
    if (peerConnection == null || _remoteDescriptionSet || _terminal) return;
    await peerConnection.setRemoteDescription(
      RTCSessionDescription(answer.sdp, answer.type),
    );
    _remoteDescriptionSet = true;
    await _flushCandidates();
    _setConnected();
  }

  Future<void> _handleIceCandidate(CallIceCandidate candidate) async {
    if (_peerConnection == null || !_remoteDescriptionSet) {
      _queuedCandidates.add(candidate);
      return;
    }
    await _peerConnection!.addCandidate(
      RTCIceCandidate(
        candidate.candidate,
        candidate.sdpMid,
        candidate.sdpMLineIndex,
      ),
    );
  }

  Future<void> _flushCandidates() async {
    final callId = _callId;
    if (callId == null) return;
    _queuedCandidates.addAll(_socket?.takePendingIce(callId) ?? const []);
    while (_queuedCandidates.isNotEmpty) {
      final candidate = _queuedCandidates.removeAt(0);
      await _peerConnection?.addCandidate(
        RTCIceCandidate(
          candidate.candidate,
          candidate.sdpMid,
          candidate.sdpMLineIndex,
        ),
      );
    }
  }

  void _setConnected() {
    if (!mounted || _connected) return;
    setState(() => _connected = true);
    CallRingtoneService.instance.stop();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  Future<void> _toggleMute() async {
    final track = _localStream?.getAudioTracks().firstOrNull;
    if (track == null) return;
    track.enabled = !track.enabled;
    setState(() => _muted = !track.enabled);
  }

  Future<void> _toggleCamera() async {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track == null) return;
    track.enabled = !track.enabled;
    setState(() => _cameraEnabled = track.enabled);
  }

  Future<void> _switchCamera() async {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track != null) await Helper.switchCamera(track);
  }

  Future<void> _toggleSpeaker() async {
    final speakerOn = !_speakerOn;
    try {
      await Helper.setSpeakerphoneOn(speakerOn);
      if (mounted) setState(() => _speakerOn = speakerOn);
    } catch (_) {
      // Not every desktop audio device exposes a speakerphone route.
    }
  }

  String _mediaError(Object error) {
    final value = error.toString().toLowerCase();
    if (value.contains('permission') || value.contains('denied')) {
      return 'Allow camera and microphone access to start this call.';
    }
    return 'Could not start the call. Please check your camera and microphone.';
  }

  Future<void> _handleRemoteEnd(String reason) async {
    if (_terminal) return;
    _terminal = true;
    await CallRingtoneService.instance.stop();
    final callId = _callId ?? widget.offer?.callId;
    if (callId != null) await NotificationService().dismissIncomingCall(callId);
    await _disposeMedia();
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(reason)));
    }
  }

  Future<void> _endCall({String reason = 'ended'}) async {
    if (_terminal) return;
    _terminal = true;
    await CallRingtoneService.instance.stop();
    final callId = _callId ?? widget.offer?.callId;
    if (callId != null) await NotificationService().dismissIncomingCall(callId);
    if (callId != null) _socket?.endCall(callId, reason: reason);
    await _disposeMedia();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _disposeMedia() async {
    _durationTimer?.cancel();
    CallRingtoneService.instance.stop();
    final stream = _localStream;
    _localStream = null;
    for (final track in stream?.getTracks() ?? const <MediaStreamTrack>[]) {
      track.stop();
    }
    await _peerConnection?.close();
    _peerConnection = null;
  }

  @override
  void dispose() {
    _answerSub?.cancel();
    _iceSub?.cancel();
    _endSub?.cancel();
    _readySub?.cancel();
    _notificationActionSub?.cancel();
    _durationTimer?.cancel();
    if (!_terminal) {
      final callId = _callId ?? widget.offer?.callId;
      if (callId != null) _socket?.endCall(callId, reason: 'ended');
    }
    _disposeMedia();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  String get _name => widget.otherParticipant.displayName?.isNotEmpty == true
      ? widget.otherParticipant.displayName!
      : '@${widget.otherParticipant.username}';

  String get _timeLabel {
    if (!_connected) {
      return widget.isIncoming
          ? 'Incoming ${widget.kind.label.toLowerCase()}'
          : 'Calling…';
    }
    final minutes = (_seconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final hasRemoteVideo =
        widget.kind == CallKind.video && _remoteRenderer.srcObject != null;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (hasRemoteVideo)
              RTCVideoView(_remoteRenderer)
            else
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_deepViolet, Color(0xFF100D25)],
                  ),
                ),
              ),
            if (!hasRemoteVideo)
              _RemoteIdentity(name: _name, user: widget.otherParticipant),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                child: Column(
                  children: [
                    Text(
                      _name,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _error ?? _timeLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: _error == null
                            ? Colors.white70
                            : const Color(0xFFFFB4B4),
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    if (widget.kind == CallKind.video &&
                        _localRenderer.srcObject != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: SizedBox(
                            width: 118,
                            height: 168,
                            child: _cameraEnabled
                                ? RTCVideoView(_localRenderer, mirror: true)
                                : const ColoredBox(color: Color(0xFF2A2547)),
                          ),
                        ),
                      ),
                    const SizedBox(height: 22),
                    if (widget.isIncoming && _callId == null)
                      _IncomingControls(
                        busy: _starting,
                        onDecline: () => _endCall(reason: 'declined'),
                        onAccept: _acceptIncoming,
                      )
                    else
                      _CallControls(
                        isVideo: widget.kind == CallKind.video,
                        muted: _muted,
                        cameraEnabled: _cameraEnabled,
                        speakerOn: _speakerOn,
                        onMute: _toggleMute,
                        onCamera: _toggleCamera,
                        onSwitchCamera: _switchCamera,
                        onSpeaker: _toggleSpeaker,
                        onHangUp: _endCall,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteIdentity extends StatelessWidget {
  const _RemoteIdentity({required this.name, required this.user});

  final String name;
  final PostAuthor user;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 142,
          height: 142,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 38,
              ),
            ],
          ),
          child: ClipOval(
            child: user.avatarUrl == null
                ? const ColoredBox(
                    color: Color(0xFFECE9FF),
                    child: Icon(Icons.person_rounded, size: 58, color: _violet),
                  )
                : CachedNetworkImage(
                    imageUrl: user.avatarUrl!,
                    fit: BoxFit.cover,
                  ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          name,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
      ],
    ),
  );
}

class _IncomingControls extends StatelessWidget {
  const _IncomingControls({
    required this.busy,
    required this.onDecline,
    required this.onAccept,
  });

  final bool busy;
  final VoidCallback onDecline;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _RoundControl(
        icon: Icons.call_end_rounded,
        color: const Color(0xFFFF4F5E),
        onTap: busy ? null : onDecline,
      ),
      _RoundControl(
        icon: Icons.call_rounded,
        color: const Color(0xFF50C878),
        onTap: busy ? null : onAccept,
      ),
    ],
  );
}

class _CallControls extends StatelessWidget {
  const _CallControls({
    required this.isVideo,
    required this.muted,
    required this.cameraEnabled,
    required this.speakerOn,
    required this.onMute,
    required this.onCamera,
    required this.onSwitchCamera,
    required this.onSpeaker,
    required this.onHangUp,
  });

  final bool isVideo;
  final bool muted;
  final bool cameraEnabled;
  final bool speakerOn;
  final VoidCallback onMute;
  final VoidCallback onCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onSpeaker;
  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 14,
    runSpacing: 12,
    children: [
      _RoundControl(
        icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
        active: muted,
        onTap: onMute,
      ),
      _RoundControl(
        icon: speakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
        active: speakerOn,
        onTap: onSpeaker,
      ),
      if (isVideo) ...[
        _RoundControl(
          icon: cameraEnabled
              ? Icons.videocam_rounded
              : Icons.videocam_off_rounded,
          active: !cameraEnabled,
          onTap: onCamera,
        ),
        _RoundControl(icon: Icons.cameraswitch_rounded, onTap: onSwitchCamera),
      ],
      _RoundControl(
        icon: Icons.call_end_rounded,
        color: const Color(0xFFFF4F5E),
        onTap: onHangUp,
      ),
    ],
  );
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.icon,
    required this.onTap,
    this.color,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final bool active;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color:
            color ??
            (active ? Colors.white : Colors.white.withValues(alpha: 0.20)),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: color == null ? 0.25 : 0.0),
        ),
      ),
      child: Icon(
        icon,
        color: color == null && active ? _deepViolet : Colors.white,
        size: 25,
      ),
    ),
  );
}
