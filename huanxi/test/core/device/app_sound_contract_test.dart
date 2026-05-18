import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('pubspec registers audio player dependency and sound assets', () {
    final pubspec = read('pubspec.yaml');

    expect(pubspec, contains('audioplayers:'));
    expect(pubspec, contains('- assets/sounds/'));
  });

  test('storage exposes sound preference toggles defaulting to enabled', () {
    final storage = read('lib/core/storage/storage.dart');

    expect(storage, contains('storageMessageSoundEnabled'));
    expect(storage, contains('storageIncomingRingtoneEnabled'));
    expect(storage, contains('isMessageSoundEnabled()'));
    expect(storage, contains('isIncomingRingtoneEnabled()'));
    expect(storage, contains('setMessageSoundEnabled(bool enabled)'));
    expect(storage, contains('setIncomingRingtoneEnabled(bool enabled)'));
    expect(storage, contains('?? true'));
  });

  test('settings page exposes separate foreground sound switches', () {
    final settings = read('lib/modules/settings/settings_page.dart');

    expect(settings, contains('消息提示音'));
    expect(settings, contains('来电铃声'));
    expect(settings, contains('isMessageSoundEnabled()'));
    expect(settings, contains('isIncomingRingtoneEnabled()'));
    expect(settings, contains('setMessageSoundEnabled'));
    expect(settings, contains('setIncomingRingtoneEnabled'));
  });

  test('app sound service owns message and incoming ringtone playback', () {
    final service = read('lib/core/device/app_sound_service.dart');

    expect(service, contains("AssetSource('sounds/message.mp3')"));
    expect(service, contains("AssetSource('sounds/incoming_call.mp3')"));
    expect(service, contains('playMessageSound()'));
    expect(service, contains('startIncomingRingtone()'));
    expect(service, contains('stopIncomingRingtone()'));
    expect(service, contains('ReleaseMode.loop'));
    expect(service, contains('isIncomingRingtoneEnabled()'));
    expect(service, contains('isMessageSoundEnabled()'));
  });

  test('main shell plays message sound with foreground and message filters', () {
    final shell = read('lib/modules/home/main_shell.dart');

    expect(shell, contains('AppSoundService.instance.playMessageSound'));
    expect(shell, contains('_shouldPlayMessageSound'));
    expect(shell, contains('AppLifecycleState.resumed'));
    expect(shell, contains('parseCallTraceMessage'));
    expect(shell, contains('_isCurrentImConversation'));
    expect(shell, contains('message.sender'));
  });

  test('incoming call page starts and stops foreground ringtone', () {
    final page = read('lib/modules/call/incoming_call_page.dart');

    expect(page, contains('AppSoundService.instance.startIncomingRingtone'));
    expect(page, contains('AppSoundService.instance.stopIncomingRingtone'));
    expect(page, contains('_stopRingtone'));
    expect(page, contains('_acceptCall()'));
    expect(page, contains('_rejectCall()'));
    expect(page, contains('dispose()'));
  });

  test('android incoming call notification uses a fresh sound channel', () {
    final notification = read(
      'android/app/src/main/kotlin/com/huanxi/huanxi/IncomingCallNotification.kt',
    );

    expect(notification, contains('star_chat_incoming_call_sound_v1'));
    expect(notification, contains('android.resource'));
    expect(notification, contains('incoming_call'));
    expect(notification, contains('setSound'));
    expect(notification, contains('AudioAttributes'));
    expect(notification, contains('USAGE_NOTIFICATION_RINGTONE'));
  });
}
