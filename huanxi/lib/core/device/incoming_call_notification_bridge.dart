import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class IncomingCallNotificationPayload {
  final int callId;
  final int peerUserId;
  final String peerName;
  final String? peerAvatar;
  final int leftSeconds;

  const IncomingCallNotificationPayload({
    required this.callId,
    required this.peerUserId,
    required this.peerName,
    required this.peerAvatar,
    required this.leftSeconds,
  });

  Map<String, dynamic> toMap() {
    return {
      'callId': callId,
      'peerUserId': peerUserId,
      'peerName': peerName,
      'peerAvatar': peerAvatar ?? '',
      'leftSeconds': leftSeconds,
    };
  }

  static IncomingCallNotificationPayload? fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return null;
    final callId = _toInt(map['callId'] ?? map['call_id']);
    final peerUserId = _toInt(map['peerUserId'] ?? map['peer_user_id']);
    if (callId <= 0 || peerUserId <= 0) return null;
    return IncomingCallNotificationPayload(
      callId: callId,
      peerUserId: peerUserId,
      peerName: '${map['peerName'] ?? map['peer_name'] ?? '用户'}',
      peerAvatar: _emptyToNull(map['peerAvatar'] ?? map['peer_avatar']),
      leftSeconds: _toInt(map['leftSeconds'] ?? map['left_seconds'], fallback: 30),
    );
  }

  static int _toInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static String? _emptyToNull(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class IncomingCallNotificationBridge {
  IncomingCallNotificationBridge._();

  static const MethodChannel _channel = MethodChannel(
    'huanxi/incoming_call_notification',
  );

  static void configure({
    required void Function(IncomingCallNotificationPayload payload) onOpenIncomingCall,
  }) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'openIncomingCall') return;
      final payload = IncomingCallNotificationPayload.fromMap(
        call.arguments is Map ? call.arguments as Map<dynamic, dynamic> : null,
      );
      if (payload != null) {
        onOpenIncomingCall(payload);
      }
    });
  }

  static Future<IncomingCallNotificationPayload?> takeLaunchIncomingCall() async {
    if (!Platform.isAndroid) return null;
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'takeLaunchIncomingCall',
    );
    return IncomingCallNotificationPayload.fromMap(raw);
  }

  static Future<void> showIncomingCall(
    IncomingCallNotificationPayload payload,
  ) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('showIncomingCall', payload.toMap());
  }

  static Future<void> cancelIncomingCall({required int callId}) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('cancelIncomingCall', {'callId': callId});
  }
}
