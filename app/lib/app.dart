// TODO(share-intent): receive_sharing_intent requires Android compileSdk 37,
// which currently fails to resolve on this toolchain (Google's package
// manifest for the very-new API 37 platform uses a "37.0" internal path that
// AGP's compileSdk="37" lookup can't match, even after manually fixing the
// SDK folder/manifest - it gets re-downloaded wrong on every build). Disabled
// for now so the rest of the app can build/run; re-enable once a proper
// cmdline-tools/sdkmanager install resolves the SDK 37 mismatch, then restore
// this file from git history plus the `receive_sharing_intent` pubspec dep.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/global_message_listener.dart';
import 'core/notification_service.dart';
import 'core/theme.dart';
import 'router/app_router.dart';

class OurChatApp extends ConsumerStatefulWidget {
  const OurChatApp({super.key});

  @override
  ConsumerState<OurChatApp> createState() => _OurChatAppState();
}

class _OurChatAppState extends ConsumerState<OurChatApp> {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    // The Android permission dialog needs a resumed Activity, which isn't
    // guaranteed yet during main() — ask once the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().requestPermission();
    });
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
      builder: (context, child) => GlobalMessageListener(
        scaffoldMessengerKey: _scaffoldMessengerKey,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
