import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class CallKeepAliveBridge {
  CallKeepAliveBridge._();

  static const MethodChannel _channel = MethodChannel(
    'huanxi/call_keep_alive',
  );

  static Future<bool> isServiceRunning() async {
    if (!Platform.isAndroid) return false;
    final running = await _channel.invokeMethod<bool>('isServiceRunning');
    return running ?? false;
  }

  static Future<void> startOnlineMode() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('startOnlineMode');
  }

  static Future<void> stopOnlineMode() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('stopOnlineMode');
  }

  static Future<void> startCallMode({required int callId}) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('startCallMode', {'callId': callId});
  }

  static Future<void> stopCallMode() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('stopCallMode');
  }
}
