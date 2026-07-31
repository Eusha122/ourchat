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

  static const _channelId = 'messages';
  static const _channelName = 'Messages';
  static const _channelDescription = 'Notifications for new chat messages';

  /// Sets up the plugin and notification channel. Safe to call in `main()`
  /// before `runApp()` — creates no UI, so it can't be affected by the
  /// Activity not being resumed yet.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
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
    } catch (_) {
      // Permission APIs may be unavailable in tests or unsupported platforms.
    }
  }

  /// Shows a real entry in the system notification tray/panel, the way
  /// Instagram/WhatsApp do for a new message.
  Future<void> showMessageNotification({
    required String title,
    required String body,
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
      );
    } catch (_) {
      // Silently handle error
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

  void dispose() {
    _audioPlayer?.dispose();
  }
}
