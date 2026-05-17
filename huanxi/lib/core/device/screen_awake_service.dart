import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

typedef ScreenAwakeAction = Future<void> Function();
typedef ScreenAwakeErrorLogger =
    void Function(String message, Object error, StackTrace stackTrace);

class ScreenAwakeService {
  ScreenAwakeService({
    ScreenAwakeAction? enable,
    ScreenAwakeAction? disable,
    ScreenAwakeErrorLogger? logError,
  }) : _enable = enable ?? WakelockPlus.enable,
       _disable = disable ?? WakelockPlus.disable,
       _logError = logError ?? _defaultLogError;

  static final ScreenAwakeService instance = ScreenAwakeService();

  final ScreenAwakeAction _enable;
  final ScreenAwakeAction _disable;
  final ScreenAwakeErrorLogger _logError;
  bool _globalEnabled = false;

  bool get isGlobalEnabled => _globalEnabled;

  Future<void> enableGlobal() async {
    _globalEnabled = true;
    await _runSafely(_enable, '启用屏幕常亮失败');
  }

  Future<void> disableGlobal() async {
    _globalEnabled = false;
    await _runSafely(_disable, '关闭屏幕常亮失败');
  }

  Future<void> reapplyIfNeeded() async {
    if (!_globalEnabled) return;
    await _runSafely(_enable, '恢复屏幕常亮失败');
  }

  Future<void> _runSafely(ScreenAwakeAction action, String message) async {
    try {
      await action();
    } catch (error, stackTrace) {
      _logError(message, error, stackTrace);
    }
  }

  static void _defaultLogError(
    String message,
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint('[ScreenAwake] $message: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
