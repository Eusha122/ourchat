import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio/just_audio.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  AudioPlayer? _audioPlayer;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _notificationId = 0;
  final _callActionController =
      StreamController<CallNotificationAction>.broadcast();
  final _messageTapController = StreamController<String>.broadcast();
  final _activeCallNotifications = <String, int>{};
  static const _conversationPayloadPrefix = 'conversation:';

  static const _channelId = 'messages';
  static const _channelName = 'Messages';
  static const _channelDescription = 'Notifications for new chat messages';
  static const _callChannelId = 'calls';
  static const acceptCallAction = 'accept_call';
  static const declineCallAction = 'decline_call';

  Stream<CallNotificationAction> get onCallAction =>
      _callActionController.stream;
  Stream<String> get onMessageTap => _messageTapController.stream;

  /// Sets up the plugin and notification channel. Safe to call in `main()`
  /// before `runApp()` — creates no UI, so it can't be affected by the
  /// Activity not being resumed yet.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    const callChannel = AndroidNotificationChannel(
      _callChannelId,
      'Calls',
      description: 'Incoming call alerts',
      importance: Importance.max,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(callChannel);
  }

  /// Requests the Android 13+ POST_NOTIFICATIONS permission. Must run
  /// *after* the first frame — the OS permission dialog needs a resumed
  /// Activity, which doesn't exist yet during `main()`, so calling this too
  /// early silently no-ops instead of prompting.
  Future<void> requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestFullScreenIntentPermission();
    } catch (_) {
      // Permission APIs may be unavailable in tests or unsupported platforms.
    }
  }

  /// Shows a real entry in the system notification tray/panel, the way
  /// Instagram/WhatsApp do for a new message.
  Future<void> showMessageNotification({
    required String title,
    required String body,
    String? conversationId,
  }) async {
    try {
      // This makes the service resilient if a platform lifecycle race means
      // `main()` has not completed initialization yet.
      await init();
      await _plugin.show(
        _notificationId++,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            // The sound is played separately via just_audio (our custom
            // clip), so the system notification itself stays silent to
            // avoid it playing twice.
            playSound: false,
          ),
        ),
        payload: conversationId == null
            ? null
            : '$_conversationPayloadPrefix$conversationId',
      );
    } catch (_) {
      // Silently handle error
    }
  }

  /// Checks whether the app process was just cold-started by tapping a
  /// message notification (as opposed to the tap-while-running path handled
  /// by [onMessageTap]), returning the conversation to open if so.
  Future<String?> takeColdStartConversationId() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return null;
      final payload = details?.notificationResponse?.payload;
      if (payload == null || !payload.startsWith(_conversationPayloadPrefix)) {
        return null;
      }
      return payload.substring(_conversationPayloadPrefix.length);
    } catch (_) {
      return null;
    }
  }

  Future<void> playMessageNotification() async {
    try {
      _audioPlayer ??= AudioPlayer();
      await _audioPlayer!.setAsset('assets/sounds/message_notification.mp3');
      await _audioPlayer!.play();
    } catch (_) {
      // Silently handle error
    }
  }

  Future<void> showIncomingCallNotification({
    required String callId,
    required String caller,
    required bool isVideo,
  }) async {
    try {
      await init();
      final notificationId = _activeCallNotifications.putIfAbsent(
        callId,
        () => _notificationId++,
      );
      await _plugin.show(
        notificationId,
        'Incoming ${isVideo ? 'video' : 'voice'} call',
        '$caller is calling you',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _callChannelId,
            'Calls',
            channelDescription: 'Incoming call alerts',
            importance: Importance.max,
            priority: Priority.max,
            playSound: false,
            category: AndroidNotificationCategory.call,
            ongoing: true,
            autoCancel: false,
            fullScreenIntent: true,
            actions: <AndroidNotificationAction>[
              AndroidNotificationAction(
                acceptCallAction,
                'Accept',
                showsUserInterface: true,
                cancelNotification: false,
              ),
              AndroidNotificationAction(
                declineCallAction,
                'Decline',
                showsUserInterface: true,
                cancelNotification: false,
              ),
            ],
          ),
        ),
        payload: callId,
      );
    } catch (_) {}
  }

  Future<void> dismissIncomingCall(String callId) async {
    final notificationId = _activeCallNotifications.remove(callId);
    if (notificationId == null) return;
    try {
      await _plugin.cancel(notificationId);
    } catch (_) {}
  }

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    if (payload.startsWith(_conversationPayloadPrefix)) {
      _messageTapController.add(
        payload.substring(_conversationPayloadPrefix.length),
      );
      return;
    }

    final action = response.actionId;
    if (action == null) return;
    if (action == acceptCallAction || action == declineCallAction) {
      _callActionController.add(CallNotificationAction(payload, action));
    }
  }

  void dispose() {
    _audioPlayer?.dispose();
    _callActionController.close();
    _messageTapController.close();
  }
}

class CallNotificationAction {
  const CallNotificationAction(this.callId, this.actionId);

  final String callId;
  final String actionId;
}
