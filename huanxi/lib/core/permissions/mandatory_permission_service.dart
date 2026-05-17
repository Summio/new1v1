import 'dart:io' show Platform;

import 'package:permission_handler/permission_handler.dart';

import '../device/call_keep_alive_bridge.dart';
import '../../services/websocket_service.dart';

enum MandatoryPermissionKind {
  notification,
  camera,
  microphone,
  androidKeepAlive,
}

class MandatoryPermissionCheck {
  final MandatoryPermissionKind kind;
  final bool granted;
  final bool required;
  final bool shouldOpenSettings;

  const MandatoryPermissionCheck({
    required this.kind,
    required this.granted,
    this.required = true,
    this.shouldOpenSettings = false,
  });

  String get title {
    switch (kind) {
      case MandatoryPermissionKind.notification:
        return '通知权限';
      case MandatoryPermissionKind.camera:
        return '相机权限';
      case MandatoryPermissionKind.microphone:
        return '麦克风权限';
      case MandatoryPermissionKind.androidKeepAlive:
        return '后台接听服务';
    }
  }

  String get description {
    switch (kind) {
      case MandatoryPermissionKind.notification:
        return '用于显示后台在线、来电和通话状态通知';
      case MandatoryPermissionKind.camera:
        return '用于视频通话和真人认证';
      case MandatoryPermissionKind.microphone:
        return '用于语音和视频通话';
      case MandatoryPermissionKind.androidKeepAlive:
        return '用于保持后台在线接听状态';
    }
  }
}

class MandatoryPermissionState {
  final List<MandatoryPermissionCheck> checks;

  const MandatoryPermissionState({required this.checks});

  bool get allGranted => checks.every((item) => item.granted);

  bool get requiredGranted =>
      checks.where((item) => item.required).every((item) => item.granted);

  bool get keepAliveGranted => checks
      .where((item) => item.kind == MandatoryPermissionKind.androidKeepAlive)
      .any((item) => item.granted);

  List<MandatoryPermissionCheck> get missing =>
      checks.where((item) => !item.granted).toList(growable: false);

  List<MandatoryPermissionCheck> get requiredMissing => checks
      .where((item) => item.required && !item.granted)
      .toList(growable: false);

  bool get needsSettings =>
      requiredMissing.any((item) => item.shouldOpenSettings);
}

class MandatoryPermissionService {
  MandatoryPermissionService._();

  static final MandatoryPermissionService instance =
      MandatoryPermissionService._();

  MandatoryPermissionState? _lastState;

  bool get allGranted => _lastState?.allGranted ?? false;

  bool get requiredGranted => _lastState?.requiredGranted ?? false;

  Future<MandatoryPermissionState> check() async {
    final checks = <MandatoryPermissionCheck>[
      await _checkPermission(
        MandatoryPermissionKind.camera,
        Permission.camera,
      ),
      await _checkPermission(
        MandatoryPermissionKind.microphone,
        Permission.microphone,
      ),
    ];

    if (Platform.isAndroid || Platform.isIOS) {
      checks.insert(
        0,
        await _checkPermission(
          MandatoryPermissionKind.notification,
          Permission.notification,
          required: false,
        ),
      );
    }

    if (Platform.isAndroid) {
      final keepAliveRunning = await _isKeepAliveRunning();
      checks.add(
        MandatoryPermissionCheck(
          kind: MandatoryPermissionKind.androidKeepAlive,
          granted: keepAliveRunning,
          required: false,
        ),
      );
    }

    _lastState = MandatoryPermissionState(checks: checks);
    return _lastState!;
  }

  Future<MandatoryPermissionState> requestMissing() async {
    final current = await check();
    for (final item in current.requiredMissing) {
      if (item.shouldOpenSettings) {
        await openAppSettings();
        return check();
      }
      final permission = _permissionForKind(item.kind);
      if (permission != null) {
        await permission.request();
      }
    }
    return check();
  }

  Future<MandatoryPermissionState> ensureReadyForLoggedInUser() async {
    var state = await requestMissing();
    if (state.requiredGranted && Platform.isAndroid) {
      await _bestEffortSetOnline();
      state = await check();
    }
    return state;
  }

  Future<MandatoryPermissionState> startKeepAliveForLoggedInUser() async {
    var state = await requestMissing();
    if (!Platform.isAndroid || !state.requiredGranted) {
      return state;
    }
    try {
      await CallKeepAliveBridge.startOnlineMode();
      await _bestEffortSetOnline();
    } catch (_) {}
    state = await check();
    return state;
  }

  Future<void> stopKeepAliveForLogout() async {
    if (Platform.isAndroid) {
      await CallKeepAliveBridge.stopOnlineMode();
    }
  }

  Future<MandatoryPermissionCheck> _checkPermission(
    MandatoryPermissionKind kind,
    Permission permission, {
    bool required = true,
  }) async {
    final status = await permission.status;
    return MandatoryPermissionCheck(
      kind: kind,
      granted: status.isGranted || status.isLimited,
      required: required,
      shouldOpenSettings: status.isPermanentlyDenied || status.isRestricted,
    );
  }

  Future<bool> _isKeepAliveRunning() async {
    try {
      return await CallKeepAliveBridge.isServiceRunning();
    } catch (_) {
      return false;
    }
  }

  Future<void> _bestEffortSetOnline() async {
    try {
      await WsService.instance.connect();
      await WsService.instance.sendSetOnlineStatus(true);
    } catch (_) {}
  }

  Permission? _permissionForKind(MandatoryPermissionKind kind) {
    switch (kind) {
      case MandatoryPermissionKind.notification:
        return Permission.notification;
      case MandatoryPermissionKind.camera:
        return Permission.camera;
      case MandatoryPermissionKind.microphone:
        return Permission.microphone;
      case MandatoryPermissionKind.androidKeepAlive:
        return null;
    }
  }
}
