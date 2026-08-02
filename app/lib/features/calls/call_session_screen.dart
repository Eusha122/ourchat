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
import '../chat/data/conversations_api.dart';
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
  final _seenIceCandidates = <String>{};

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  StreamSubscription<CallAnswer>? _answerSub;
  StreamSubscription<CallIceCandidate>? _iceSub;
  StreamSubscription<CallEndedEvent>? _endSub;
  StreamSubscription<String>? _readySub;
  StreamSubscription<String>? _acceptedSub;
  StreamSubscription<CallNotificationAction>? _notificationActionSub;
  ProviderSubscription<SocketService?>? _socketProviderSub;
  SocketService? _signalSocket;
  Timer? _durationTimer;
  Timer? _connectionTimeout;
  Timer? _iceDisconnectTimer;
  Future<void> _iceOperation = Future<void>.value();
  String? _callId;
  bool _remoteDescriptionSet = false;
  bool _offerReady = false;
  bool _muted = false;
  bool _cameraEnabled = true;
  bool _speakerOn = true;
  bool _connected = false;
  bool _accepted = false;
  bool _reconnecting = false;
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
    _socketProviderSub = ref.listenManual(socketServiceProvider, (
      previous,
      next,
    ) {
      _bindSignalSocket(next);
    }, fireImmediately: true);
    _boot();
  }

  Future<void> _boot() async {
    await _initializeRenderers();
    if (!mounted) return;
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

  void _bindSignalSocket(SocketService? socket) {
    if (identical(_signalSocket, socket)) return;
    _signalSocket = socket;
    _answerSub?.cancel();
    _iceSub?.cancel();
    _endSub?.cancel();
    _readySub?.cancel();
    _acceptedSub?.cancel();
    if (socket == null) return;
    _answerSub = socket.onCallAnswer.listen((answer) {
      if (answer.callId == _callId) {
        unawaited(_handleAnswer(answer).catchError(_handleSignalError));
      }
    });
    _iceSub = socket.onCallIce.listen((candidate) {
      if (candidate.callId == _callId) {
        unawaited(
          _handleIceCandidate(candidate).catchError(_handleSignalError),
        );
      }
    });
    _endSub = socket.onCallEnded.listen((event) {
      if (event.callId == _callId) _handleRemoteEnd(event.reason);
    });
    _readySub = socket.onCallReady.listen((callId) {
      if (callId != _callId) return;
      _markOfferReady();
    });
    _acceptedSub = socket.onCallAccepted.listen((callId) {
      if (callId == _callId) _markAccepted();
    });
  }

  String _newCallId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 32).toRadixString(36)}';

  Future<void> _startOutgoing() async {
    _callId = _newCallId();
    setState(() => _starting = true);
    CallRingtoneService.instance.playOutgoing();
    try {
      final socket = _socket;
      if (socket == null || !await socket.ensureConnected()) {
        throw StateError('Signalling connection unavailable');
      }
      await _prepareConnection();
      final peerConnection = _peerConnection!;
      final offer = await peerConnection.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.kind == CallKind.video,
      });
      await peerConnection.setLocalDescription(offer);
      if (offer.sdp == null || offer.type == null) {
        throw StateError('Connection unavailable');
      }
      final relayed = await socket.sendCallOffer(
        callId: _callId!,
        conversationId: widget.conversationId,
        kind: widget.kind,
        type: offer.type!,
        sdp: offer.sdp!,
      );
      if (!relayed) throw StateError('Signalling connection unavailable');
      _markOfferReady();
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
      final socket = _socket;
      if (socket == null || !await socket.ensureConnected()) {
        throw StateError('Signalling connection unavailable');
      }
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
      if (answer.sdp == null || answer.type == null) {
        throw StateError('Connection unavailable');
      }
      final relayed = await socket.sendCallAnswer(
        callId: _callId!,
        type: answer.type!,
        sdp: answer.sdp!,
      );
      if (!relayed) throw StateError('Signalling connection unavailable');
      _markAccepted();
      _startConnectionTimeout();
    } catch (error) {
      if (mounted) setState(() => _error = _mediaError(error));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _prepareConnection() async {
    final iceServers = await _loadIceServers();
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'channelCount': 1,
      },
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
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    });
    _peerConnection = peerConnection;
    for (final track in stream.getTracks()) {
      await peerConnection.addTrack(track, stream);
    }
    peerConnection.onTrack = (event) => unawaited(_attachRemoteTrack(event));
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
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _setConnected();
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _scheduleIceDisconnectCheck();
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          unawaited(_endCall(reason: 'connection_failed'));
        case RTCPeerConnectionState.RTCPeerConnectionStateNew:
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          break;
      }
    };
    peerConnection.onIceConnectionState = (state) {
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _iceDisconnectTimer?.cancel();
          _setConnected();
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          _scheduleIceDisconnectCheck();
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
        case RTCIceConnectionState.RTCIceConnectionStateClosed:
          unawaited(_endCall(reason: 'connection_failed'));
        case RTCIceConnectionState.RTCIceConnectionStateNew:
        case RTCIceConnectionState.RTCIceConnectionStateChecking:
        case RTCIceConnectionState.RTCIceConnectionStateCount:
          break;
      }
    };
    try {
      _speakerOn = widget.kind == CallKind.video;
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (_) {
      // Desktop and some Android audio routes do not expose speaker routing.
    }
  }

  Future<List<Map<String, dynamic>>> _loadIceServers() async {
    try {
      final servers = await ref
          .read(conversationsApiProvider)
          .fetchCallIceServers();
      if (servers.isNotEmpty) return servers;
    } on ConversationsApiException {
      // An older backend should still allow a best-effort direct STUN call.
    }
    return const [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];
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

  Future<void> _attachRemoteTrack(RTCTrackEvent event) async {
    if (_terminal) return;
    event.track.enabled = true;
    MediaStream stream;
    if (event.streams.isNotEmpty) {
      stream = event.streams.first;
    } else {
      stream = _remoteStream ??= await createLocalMediaStream(
        'remote-${_callId ?? 'call'}',
      );
      if (!stream.getTracks().any((track) => track.id == event.track.id)) {
        await stream.addTrack(event.track);
      }
    }
    _remoteStream = stream;
    _remoteRenderer.srcObject = stream;
    if (mounted) setState(() {});
  }

  Future<void> _handleAnswer(CallAnswer answer) async {
    final peerConnection = _peerConnection;
    if (peerConnection == null || _remoteDescriptionSet || _terminal) return;
    _markAccepted();
    await peerConnection.setRemoteDescription(
      RTCSessionDescription(answer.sdp, answer.type),
    );
    _remoteDescriptionSet = true;
    await _flushCandidates();
  }

  void _handleSignalError(Object error) {
    if (!mounted || _terminal) return;
    setState(() => _error = _mediaError(error));
  }

  void _markOfferReady() {
    if (_offerReady || _terminal) return;
    _offerReady = true;
    _flushOutgoingIce();
    _startConnectionTimeout();
  }

  void _markAccepted() {
    if (_terminal) return;
    CallRingtoneService.instance.stop();
    _connectionTimeout?.cancel();
    _startConnectionTimeout();
    if (!mounted || _accepted) return;
    setState(() {
      _accepted = true;
      _reconnecting = false;
    });
  }

  Future<void> _handleIceCandidate(CallIceCandidate candidate) async {
    final key =
        '${candidate.candidate}|${candidate.sdpMid}|${candidate.sdpMLineIndex}';
    if (!_seenIceCandidates.add(key)) return;
    if (_peerConnection == null || !_remoteDescriptionSet) {
      _queuedCandidates.add(candidate);
      return;
    }
    await _enqueueRemoteCandidate(candidate);
  }

  /// Native WebRTC expects remote candidates in order. Socket callbacks are
  /// asynchronous, so serialising adds prevents a fast mobile connection from
  /// racing addCandidate calls before its description is fully applied.
  Future<void> _enqueueRemoteCandidate(CallIceCandidate candidate) {
    _iceOperation = _iceOperation.then((_) async {
      final peerConnection = _peerConnection;
      if (_terminal || peerConnection == null || !_remoteDescriptionSet) {
        return;
      }
      try {
        await peerConnection.addCandidate(
          RTCIceCandidate(
            candidate.candidate,
            candidate.sdpMid,
            candidate.sdpMLineIndex,
          ),
        );
      } catch (_) {
        // A stale candidate can arrive after renegotiation or teardown. The
        // next viable host/srflx/relay candidate remains usable, so ignore it.
      }
    });
    return _iceOperation;
  }

  Future<void> _flushCandidates() async {
    final callId = _callId;
    if (callId == null) return;
    final pending =
        _socket?.takePendingIce(callId) ?? const <CallIceCandidate>[];
    while (_queuedCandidates.isNotEmpty) {
      final candidate = _queuedCandidates.removeAt(0);
      await _enqueueRemoteCandidate(candidate);
    }
    // SocketService retains candidates that arrived before this screen was
    // mounted. Candidates also delivered live are deduplicated above.
    for (final candidate in pending) {
      await _handleIceCandidate(candidate);
    }
  }

  void _setConnected() {
    if (!mounted || _connected) return;
    setState(() {
      _accepted = true;
      _connected = true;
      _reconnecting = false;
    });
    _connectionTimeout?.cancel();
    _iceDisconnectTimer?.cancel();
    CallRingtoneService.instance.stop();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  void _startConnectionTimeout() {
    _connectionTimeout?.cancel();
    _connectionTimeout = Timer(const Duration(seconds: 35), () {
      if (_terminal || _connected) return;
      _endCall(reason: 'connection_failed');
    });
  }

  void _scheduleIceDisconnectCheck() {
    if (_terminal || _iceDisconnectTimer?.isActive == true) return;
    if (_connected && mounted) setState(() => _reconnecting = true);
    // Mobile radios routinely report a brief disconnected ICE state while
    // moving between Wi-Fi and LTE. Give ICE time to recover before ending.
    _iceDisconnectTimer = Timer(const Duration(seconds: 10), () {
      if (!_terminal) _endCall(reason: 'connection_failed');
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
    if (value.contains('signalling') ||
        value.contains('connection unavailable')) {
      return 'Reconnecting. Please try the call again.';
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
    _connectionTimeout?.cancel();
    _iceDisconnectTimer?.cancel();
    CallRingtoneService.instance.stop();
    final stream = _localStream;
    _localStream = null;
    for (final track in stream?.getTracks() ?? const <MediaStreamTrack>[]) {
      track.stop();
    }
    await _peerConnection?.close();
    _peerConnection = null;
    _remoteRenderer.srcObject = null;
    _remoteStream = null;
  }

  @override
  void dispose() {
    _answerSub?.cancel();
    _iceSub?.cancel();
    _endSub?.cancel();
    _readySub?.cancel();
    _acceptedSub?.cancel();
    _notificationActionSub?.cancel();
    _socketProviderSub?.close();
    _durationTimer?.cancel();
    _connectionTimeout?.cancel();
    _iceDisconnectTimer?.cancel();
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
    if (_reconnecting) return 'Reconnecting...';
    if (!_connected && _accepted) return 'Connecting...';
    if (!_connected) {
      return widget.isIncoming
          ? 'Incoming ${widget.kind.label.toLowerCase()}'
          : 'Calling...';
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
