import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../storage/storage.dart';

class AppSoundService {
  AppSoundService._();

  static final AppSoundService instance = AppSoundService._();

  final AudioPlayer _messagePlayer = AudioPlayer();
  final AudioPlayer _incomingPlayer = AudioPlayer();
  bool _incomingPlaying = false;

  Future<void> playMessageSound() async {
    if (!StorageService.isMessageSoundEnabled()) {
      return;
    }
    try {
      await _messagePlayer.stop();
      await _messagePlayer.setReleaseMode(ReleaseMode.release);
      await _messagePlayer.play(AssetSource('sounds/message.mp3'));
    } catch (e) {
      debugPrint('[SOUND] play message failed: $e');
    }
  }

  Future<void> startIncomingRingtone() async {
    if (_incomingPlaying || !StorageService.isIncomingRingtoneEnabled()) {
      return;
    }
    try {
      _incomingPlaying = true;
      await _incomingPlayer.setReleaseMode(ReleaseMode.loop);
      await _incomingPlayer.play(AssetSource('sounds/incoming_call.mp3'));
    } catch (e) {
      _incomingPlaying = false;
      debugPrint('[SOUND] start incoming ringtone failed: $e');
    }
  }

  Future<void> stopIncomingRingtone() async {
    if (!_incomingPlaying) {
      return;
    }
    try {
      await _incomingPlayer.stop();
    } catch (e) {
      debugPrint('[SOUND] stop incoming ringtone failed: $e');
    } finally {
      _incomingPlaying = false;
    }
  }
}
