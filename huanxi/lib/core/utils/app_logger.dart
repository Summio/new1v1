import 'dart:convert';

import 'package:flutter/foundation.dart';

class AppLogger {
  AppLogger._();

  static const String _redacted = '***';
  static const Set<String> _sensitiveKeys = {
    'authorization',
    'token',
    'access_token',
    'refresh_token',
    'usersig',
    'user_sig',
    'password',
    'phone',
    'mobile',
    'account_no',
    'real_name',
  };

  static void debug(String message) {
    if (!kDebugMode) return;
    debugPrint(message);
  }

  static void debugJson(String message, dynamic payload) {
    if (!kDebugMode) return;
    debugPrint('$message ${safeJson(payload)}');
  }

  static String safeJson(dynamic value) {
    try {
      final redacted = redact(value);
      return redacted is String ? redacted : jsonEncode(redacted);
    } catch (_) {
      return _redacted;
    }
  }

  static dynamic redact(dynamic value) {
    if (value is Map) {
      return value.map((key, mapValue) {
        final keyText = key.toString();
        return MapEntry(
          key,
          _isSensitiveKey(keyText) ? _redacted : redact(mapValue),
        );
      });
    }
    if (value is Iterable) {
      return value.map(redact).toList(growable: false);
    }
    return value;
  }

  static bool _isSensitiveKey(String key) {
    final normalized = key.trim().toLowerCase().replaceAll('-', '_');
    return _sensitiveKeys.contains(normalized);
  }
}
