import 'package:just_audio/just_audio.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  AudioPlayer? _audioPlayer;

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
