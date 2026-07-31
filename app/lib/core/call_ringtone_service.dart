import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum IncomingRingtone { defaultTone, lulu }

extension IncomingRingtoneDetails on IncomingRingtone {
  String get id => name;

  String get label => switch (this) {
    IncomingRingtone.defaultTone => 'Default',
    IncomingRingtone.lulu => 'Lulu ringtone',
  };

  String get assetPath => switch (this) {
    IncomingRingtone.defaultTone => 'assets/sounds/incoming_default.mp3',
    IncomingRingtone.lulu => 'assets/sounds/incoming_lulu.mp3',
  };
}

class CallRingtoneService {
  CallRingtoneService._();

  static final instance = CallRingtoneService._();
  static const _preferenceKey = 'incoming_call_ringtone';
  static const _outgoingAsset = 'assets/sounds/outgoing_call.mp3';

  final _player = AudioPlayer();
  IncomingRingtone _selected = IncomingRingtone.defaultTone;
  bool _loaded = false;

  IncomingRingtone get selected => _selected;

  Future<void> init() async {
    if (_loaded) return;
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_preferenceKey);
    _selected = IncomingRingtone.values.firstWhere(
      (tone) => tone.id == value,
      orElse: () => IncomingRingtone.defaultTone,
    );
    _loaded = true;
  }

  Future<void> setIncomingRingtone(IncomingRingtone ringtone) async {
    await init();
    _selected = ringtone;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, ringtone.id);
  }

  Future<void> preview(IncomingRingtone ringtone) async {
    await _playAsset(ringtone.assetPath, loop: false);
  }

  Future<void> playIncoming() async {
    await init();
    await _playAsset(_selected.assetPath, loop: true);
  }

  Future<void> playOutgoing() => _playAsset(_outgoingAsset, loop: true);

  Future<void> _playAsset(String path, {required bool loop}) async {
    try {
      await _player.stop();
      await _player.setLoopMode(loop ? LoopMode.one : LoopMode.off);
      await _player.setAsset(path);
      await _player.play();
    } catch (_) {
      // A ringtone failure should never prevent the call itself from working.
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }
}
