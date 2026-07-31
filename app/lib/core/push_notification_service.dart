import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import 'notification_service.dart';

/// Runs in a separate, freshly spawned isolate whenever a push arrives while
/// the app is backgrounded or fully killed — none of the app's existing
/// state (Riverpod, sockets, even Firebase itself) exists here, so anything
/// this needs must be set up from scratch.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService().init();

  final data = message.data;
  if (data['type'] != 'message') return;
  await NotificationService().showMessageNotification(
    title: (data['title'] as String?) ?? 'New message',
    body: (data['body'] as String?) ?? 'Sent a message',
    conversationId: data['conversationId'] as String?,
  );
}

/// Data-only pushes (see backend `lib/push.ts`) are handled entirely by
/// [firebaseMessagingBackgroundHandler] / this service — Android never
/// auto-displays anything for them on its own.
class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  bool _listening = false;

  /// Fetches the current FCM token and hands it to [onToken] (register with
  /// the backend), then keeps doing so whenever the token rotates. Android
  /// only — iOS isn't wired up on the backend/app yet.
  Future<void> start(Future<void> Function(String token) onToken) async {
    if (kIsWeb || !Platform.isAndroid) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await onToken(token);

    if (_listening) return;
    _listening = true;
    FirebaseMessaging.instance.onTokenRefresh.listen(onToken);

    // The app is already open here (foreground or alive-in-background), so
    // the socket-based path in GlobalMessageListener already delivers and
    // displays this — showing it again from the FCM side would double it up.
    FirebaseMessaging.onMessage.listen((_) {});
  }
}
