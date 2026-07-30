import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'features/share/extract_url.dart';
import 'router/app_router.dart';

/// The share-intent plugin only has Android/iOS implementations; calling it
/// on desktop/web would throw MissingPluginException.
bool get _supportsShareIntent =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

class OurChatApp extends ConsumerStatefulWidget {
  const OurChatApp({super.key});

  @override
  ConsumerState<OurChatApp> createState() => _OurChatAppState();
}

class _OurChatAppState extends ConsumerState<OurChatApp> {
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  @override
  void initState() {
    super.initState();
    if (_supportsShareIntent) {
      _handleInitialShare();
      _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
        _handleSharedFiles,
      );
    }
  }

  Future<void> _handleInitialShare() async {
    final initial = await ReceiveSharingIntent.instance.getInitialMedia();
    _handleSharedFiles(initial);
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    for (final file in files) {
      final url = extractUrl(file.path);
      if (url != null) {
        ref.read(goRouterProvider).push('/share-target', extra: url);
        break;
      }
    }
    ReceiveSharingIntent.instance.reset();
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'OurChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
