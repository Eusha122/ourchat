import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'app.dart';
import 'core/notification_service.dart';
import 'core/push_notification_service.dart';

/// Without this, image_picker falls back to the legacy ACTION_GET_CONTENT
/// flow, which surfaces the Files/document browser. The system Photo Picker
/// is the gallery UI people expect, and it needs no storage permission.
void _useAndroidGalleryPicker() {
  final picker = ImagePickerPlatform.instance;
  if (picker is ImagePickerAndroid) {
    picker.useAndroidPhotoPicker = true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _useAndroidGalleryPicker();
  // FCM push is only configured for Android (google-services.json has no
  // Windows/desktop counterpart), so initializing it elsewhere would just
  // throw on startup for a feature that isn't wired up there anyway.
  if (defaultTargetPlatform == TargetPlatform.android) {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  await NotificationService().init();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFFF2F3FF),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const ProviderScope(child: OurChatApp()));
}
