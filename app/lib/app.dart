// TODO(share-intent): receive_sharing_intent requires Android compileSdk 37,
// which currently fails to resolve on this toolchain (Google's package
// manifest for the very-new API 37 platform uses a "37.0" internal path that
// AGP's compileSdk="37" lookup can't match, even after manually fixing the
// SDK folder/manifest - it gets re-downloaded wrong on every build). Disabled
// for now so the rest of the app can build/run; re-enable once a proper
// cmdline-tools/sdkmanager install resolves the SDK 37 mismatch, then restore
// this file from git history plus the `receive_sharing_intent` pubspec dep.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/global_message_listener.dart';
import 'core/global_call_listener.dart';
import 'core/app_update_prompt.dart';
import 'core/call_ringtone_service.dart';
import 'core/notification_service.dart';
import 'core/push_notification_service.dart';
import 'core/theme.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/chat/state/chat_providers.dart';
import 'features/users/state/users_providers.dart';
import 'router/app_router.dart';

class OurChatApp extends ConsumerStatefulWidget {
  const OurChatApp({super.key});

  @override
  ConsumerState<OurChatApp> createState() => _OurChatAppState();
}

class _OurChatAppState extends ConsumerState<OurChatApp>
    with WidgetsBindingObserver {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<String>? _messageTapSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The Android permission dialog needs a resumed Activity, which isn't
    // guaranteed yet during main() — ask once the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      NotificationService().requestPermission();
      CallRingtoneService.instance.init();

      final coldStartId = await NotificationService()
          .takeColdStartConversationId();
      if (coldStartId != null) _openConversation(coldStartId);
    });

    _messageTapSub = NotificationService().onMessageTap.listen(
      _openConversation,
    );

    // Fires immediately for an already-authenticated cold start, and again
    // on every future login — a fresh FCM token needs registering either way.
    ref.listenManual(authControllerProvider, (previous, next) {
      if (next.value?.user == null) return;
      PushNotificationService.instance.start((token) async {
        try {
          await ref
              .read(usersApiProvider)
              .registerDeviceToken(token: token, platform: 'android');
        } catch (_) {
          // Best-effort: this device just won't get pushes until the next
          // successful registration attempt. Must never block app usage.
        }
      });
    }, fireImmediately: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(socketServiceProvider)?.reconnect();
    }
  }

  void _openConversation(String conversationId) {
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    GoRouter.of(context).push('/chats/$conversationId');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageTapSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'OurChat',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.light,
      routerConfig: router,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      builder: (context, child) => AppUpdatePrompt(
        child: GlobalCallListener(
          child: GlobalMessageListener(
            scaffoldMessengerKey: _scaffoldMessengerKey,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
