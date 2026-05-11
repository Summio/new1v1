import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../core/constants/app_constants.dart';
import '../core/storage/storage.dart';

class TeenModeRecord {
  final bool enabled;
  final String salt;
  final String pinHash;

  const TeenModeRecord({
    required this.enabled,
    required this.salt,
    required this.pinHash,
  });

  bool get isValid => enabled && salt.isNotEmpty && pinHash.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'salt': salt,
    'pin_hash': pinHash,
  };

  static TeenModeRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final salt = raw['salt'];
    final pinHash = raw['pin_hash'];
    return TeenModeRecord(
      enabled: raw['enabled'] == true,
      salt: salt is String ? salt : '',
      pinHash: pinHash is String ? pinHash : '',
    );
  }
}

class TeenModeService {
  TeenModeService._();

  static final TeenModeService instance = TeenModeService._();

  static final RegExp _pinPattern = RegExp(r'^\d{4}$');
  static final Random _random = Random.secure();
  static const String _legacyEnabledKey = 'teen_mode_enabled';
  static const String _legacySaltKey = 'teen_mode_salt';
  static const String _legacyPinHashKey = 'teen_mode_pin_hash';

  bool get isEnabled => _readRecord()?.enabled == true;

  bool get hasConfiguredPin => _readRecord()?.isValid == true;

  bool get isLocked => _readRecord()?.isValid == true;

  Future<void> repairInvalidState() async {
    final raw = StorageService.getString(AppConstants.storageTeenModeState);
    if (raw != null && raw.isNotEmpty) {
      try {
        final record = TeenModeRecord.fromJson(jsonDecode(raw));
        if (record != null && record.isValid) {
          await _persistRecord(record);
          await _clearLegacyState();
          return;
        }
      } catch (_) {
        // fall through to clear invalid state
      }
      await clear();
      return;
    }

    final record = _readLegacyRecord();
    if (record == null) {
      await _clearLegacyState();
      return;
    }
    if (!record.isValid) {
      await clear();
      return;
    }
    await _persistRecord(record);
    await _clearLegacyState();
  }

  Future<void> enable(String pin) async {
    _validatePin(pin);
    final salt = _generateSalt();
    final record = TeenModeRecord(
      enabled: true,
      salt: salt,
      pinHash: _hashPin(pin, salt),
    );
    await _persistRecord(record);
    await _clearLegacyState();
  }

  Future<bool> verifyAndDisable(String pin) async {
    _validatePin(pin);
    final record = _readRecord();
    if (record == null || !record.isValid) {
      await clear();
      return false;
    }

    if (_hashPin(pin, record.salt) != record.pinHash) {
      return false;
    }

    await clear();
    return true;
  }

  Future<void> clear() async {
    await StorageService.remove(AppConstants.storageTeenModeState);
    await _clearLegacyState();
  }

  TeenModeRecord? _readRecord() {
    final raw = StorageService.getString(AppConstants.storageTeenModeState);
    if (raw != null && raw.isNotEmpty) {
      try {
        return TeenModeRecord.fromJson(jsonDecode(raw));
      } catch (_) {
        return null;
      }
    }
    return _readLegacyRecord();
  }

  Future<void> _persistRecord(TeenModeRecord record) async {
    await StorageService.saveString(
      AppConstants.storageTeenModeState,
      jsonEncode(record.toJson()),
    );
  }

  TeenModeRecord? _readLegacyRecord() {
    final enabled = StorageService.getBool(_legacyEnabledKey) == true;
    final salt = StorageService.getString(_legacySaltKey);
    final pinHash = StorageService.getString(_legacyPinHashKey);
    if (!enabled && (salt == null || salt.isEmpty) && (pinHash == null || pinHash.isEmpty)) {
      return null;
    }
    return TeenModeRecord(
      enabled: enabled,
      salt: salt ?? '',
      pinHash: pinHash ?? '',
    );
  }

  Future<void> _clearLegacyState() async {
    await StorageService.remove(_legacyEnabledKey);
    await StorageService.remove(_legacySaltKey);
    await StorageService.remove(_legacyPinHashKey);
  }

  String _generateSalt() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hashPin(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  void _validatePin(String pin) {
    if (!_pinPattern.hasMatch(pin)) {
      throw ArgumentError('PIN 必须是 4 位数字');
    }
  }
}
