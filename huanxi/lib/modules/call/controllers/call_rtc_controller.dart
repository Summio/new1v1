import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mt_plugin/mt_plugin.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/app_logger.dart';

const _rtcNoValue = Object();
const int _nativeBackCameraId = 0;
const int _nativeFrontCameraId = 1;

bool? resolveFrontCameraFromNativeState({String? facing, int? cameraId}) {
  final normalized = facing?.trim().toLowerCase();
  if (normalized == 'front') {
    return true;
  }
  if (normalized == 'back') {
    return false;
  }
  if (cameraId == _nativeFrontCameraId) {
    return true;
  }
  if (cameraId == _nativeBackCameraId) {
    return false;
  }
  return null;
}

int? resolveFrameRotationFromNativeState(dynamic frameRotation) {
  final value = (frameRotation as num?)?.toInt();
  if (value == null) {
    return null;
  }
  switch (value) {
    case 0:
    case 90:
    case 180:
    case 270:
      return value;
    default:
      return null;
  }
}

class CallRtcState {
  final bool isMicOn;
  final bool isSpeakerOn;
  final bool isCameraOn;
  final bool isFlipping;
  final bool isLoading;
  final bool isJoining;
  final bool isJoined;
  final bool isFrontCamera;
  final int? localUid;
  final int? remoteUid;
  final bool hasPeerLeft;
  final String? channelName;
  final String? errorMessage;

  const CallRtcState({
    this.isMicOn = true,
    this.isSpeakerOn = true,
    this.isCameraOn = true,
    this.isFlipping = false,
    this.isLoading = false,
    this.isJoining = false,
    this.isJoined = false,
    this.isFrontCamera = true,
    this.localUid,
    this.remoteUid,
    this.hasPeerLeft = false,
    this.channelName,
    this.errorMessage,
  });

  CallRtcState copyWith({
    bool? isMicOn,
    bool? isSpeakerOn,
    bool? isCameraOn,
    bool? isFlipping,
    bool? isLoading,
    bool? isJoining,
    bool? isJoined,
    bool? isFrontCamera,
    Object? localUid = _rtcNoValue,
    Object? remoteUid = _rtcNoValue,
    Object? hasPeerLeft = _rtcNoValue,
    Object? channelName = _rtcNoValue,
    Object? errorMessage = _rtcNoValue,
  }) {
    return CallRtcState(
      isMicOn: isMicOn ?? this.isMicOn,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isCameraOn: isCameraOn ?? this.isCameraOn,
      isFlipping: isFlipping ?? this.isFlipping,
      isLoading: isLoading ?? this.isLoading,
      isJoining: isJoining ?? this.isJoining,
      isJoined: isJoined ?? this.isJoined,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      localUid: identical(localUid, _rtcNoValue)
          ? this.localUid
          : localUid as int?,
      remoteUid: identical(remoteUid, _rtcNoValue)
          ? this.remoteUid
          : remoteUid as int?,
      hasPeerLeft: identical(hasPeerLeft, _rtcNoValue)
          ? this.hasPeerLeft
          : hasPeerLeft as bool,
      channelName: identical(channelName, _rtcNoValue)
          ? this.channelName
          : channelName as String?,
      errorMessage: identical(errorMessage, _rtcNoValue)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class CallRtcController extends StateNotifier<CallRtcState> {
  CallRtcController({required this.callId}) : super(const CallRtcState());

  final int callId;
  RtcEngine? _engine;
  RtcEngineEventHandler? _rtcEventHandler;
  bool _joinedCallbackEmitted = false;
  int _externalFrameLogCounter = 0;
  int _externalFrameHeadLogCounter = 0;
  int _externalBlackFrameCounter = 0;
  int _externalFrameWarnCounter = 0;
  int _externalPushOkCounter = 0;
  int _externalFrameRotation = 0;
  bool _isFrontCamera = true;
  bool _dropFramesDuringCameraSwitch = false;
  Timer? _cameraSwitchDropGuardTimer;
  Timer? _flipUiGuardTimer;
  Timer? _cameraSwitchResumePushTimer;
  bool _nativePushStarted = false;
  int _logSeq = 0;

  // MethodChannel 用于与原生 FaceBeauty 通信
  static const MethodChannel _beautyChannel = MethodChannel('beauty_plugin');

  RtcEngine? get engine => _engine;

  static const int _frontCameraRotation = 180;
  static const int _backCameraRotation = 0;

  int _rotationForCamera(bool isFrontCamera) {
    return isFrontCamera ? _frontCameraRotation : _backCameraRotation;
  }

  void _applyCameraFacing(bool isFrontCamera) {
    _isFrontCamera = isFrontCamera;
    _externalFrameRotation = _rotationForCamera(isFrontCamera);
    if (mounted) {
      state = state.copyWith(isFrontCamera: isFrontCamera);
    }
  }

  void _applyNativeCameraState({bool? isFrontCamera, int? frameRotation}) {
    if (isFrontCamera != null) {
      _isFrontCamera = isFrontCamera;
      _externalFrameRotation = _rotationForCamera(isFrontCamera);
      if (mounted) {
        state = state.copyWith(isFrontCamera: isFrontCamera);
      }
    }
    if (frameRotation != null) {
      _externalFrameRotation = frameRotation;
    }
  }

  void _flowLog(
    String event, {
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    _logSeq += 1;
    final snapshot = <String, Object?>{
      'seq': _logSeq,
      'event': event,
      'joined': state.isJoined,
      'joining': state.isJoining,
      'cameraOn': state.isCameraOn,
      'flipping': state.isFlipping,
      'localUid': state.localUid,
      'remoteUid': state.remoteUid,
      'rotation': _externalFrameRotation,
    }..addAll(extra);
    AppLogger.debugJson('[CALL_FLOW][callId=$callId]', snapshot);
  }

  void _finishFlipTransition({
    Duration delay = const Duration(milliseconds: 280),
  }) {
    _flipUiGuardTimer?.cancel();
    _flipUiGuardTimer = Timer(delay, () {
      if (!mounted) {
        return;
      }
      state = state.copyWith(isFlipping: false);
      _flowLog('ui.flipCamera.end');
    });
  }

  void _scheduleResumePushAfterCameraSwitch() {
    _cameraSwitchResumePushTimer?.cancel();
    _cameraSwitchResumePushTimer = Timer(const Duration(milliseconds: 320), () {
      _cameraSwitchResumePushTimer = null;
      _dropFramesDuringCameraSwitch = false;
      if (state.isJoined && state.isCameraOn) {
        _startNativePush();
      }
      if (state.isFlipping) {
        _finishFlipTransition();
      }
      _flowLog('ui.flipCamera.resumePushAfterStable');
    });
  }

  Future<dynamic> _handleNativeMethod(MethodCall call) async {
    if (call.method == 'previewReady') {
      final args = (call.arguments as Map<dynamic, dynamic>? ?? const {});
      final width = args['width'];
      final height = args['height'];
      final rawWidth = args['rawWidth'];
      final rawHeight = args['rawHeight'];
      final cameraId = (args['cameraId'] as num?)?.toInt();
      final frameRotation = resolveFrameRotationFromNativeState(
        args['frameRotation'],
      );
      final nativeIsFront = resolveFrontCameraFromNativeState(
        cameraId: cameraId,
      );
      _applyNativeCameraState(
        isFrontCamera: nativeIsFront,
        frameRotation: frameRotation,
      );
      _flowLog(
        'native.previewReady',
        extra: <String, Object?>{
          'width': width,
          'height': height,
          'rawWidth': rawWidth,
          'rawHeight': rawHeight,
          'cameraId': cameraId,
          'nativeFrameRotation': frameRotation,
          'rotation': _externalFrameRotation,
        },
      );
      if (_dropFramesDuringCameraSwitch) {
        _scheduleResumePushAfterCameraSwitch();
      } else {
        if (state.isJoined && state.isCameraOn) {
          _startNativePush();
        }
        if (state.isFlipping) {
          _finishFlipTransition();
        }
      }
      return;
    }
    if (call.method == 'cameraSwitchResult') {
      final args = (call.arguments as Map<dynamic, dynamic>? ?? const {});
      final success = args['success'] as bool? ?? true;
      final cameraId = (args['cameraId'] as num?)?.toInt();
      final from = (args['from'] as String?)?.trim().toLowerCase();
      final to = (args['to'] as String?)?.trim().toLowerCase();
      final frameRotation = resolveFrameRotationFromNativeState(
        args['frameRotation'],
      );
      final nativeFrom = resolveFrontCameraFromNativeState(facing: from);
      final nativeTo = resolveFrontCameraFromNativeState(
        facing: to,
        cameraId: cameraId,
      );
      if (success) {
        _applyNativeCameraState(
          isFrontCamera: nativeTo,
          frameRotation: frameRotation,
        );
      } else if (nativeFrom != null) {
        // 切换失败时回滚到切换前镜头，避免旋转状态错误。
        _applyNativeCameraState(
          isFrontCamera: nativeFrom,
          frameRotation: frameRotation,
        );
      } else {
        final fallbackByCameraId = resolveFrontCameraFromNativeState(
          cameraId: cameraId,
        );
        _applyNativeCameraState(
          isFrontCamera: fallbackByCameraId,
          frameRotation: frameRotation,
        );
      }
      _cameraSwitchDropGuardTimer?.cancel();
      _cameraSwitchDropGuardTimer = null;
      if (success) {
        _scheduleResumePushAfterCameraSwitch();
      } else {
        _cameraSwitchResumePushTimer?.cancel();
        _cameraSwitchResumePushTimer = null;
        _dropFramesDuringCameraSwitch = false;
        if (!success && state.isFlipping) {
          _finishFlipTransition(delay: Duration.zero);
        }
      }
      _flowLog(
        'native.cameraSwitchResult',
        extra: <String, Object?>{
          'success': success,
          'from': from ?? args['from'],
          'to': to ?? args['to'],
          'cameraId': cameraId,
          'nativeFrameRotation': frameRotation,
          'width': args['width'],
          'height': args['height'],
          'rotation': _externalFrameRotation,
        },
      );
      return;
    }
    if (call.method == 'onFrame') {
      if (_dropFramesDuringCameraSwitch) {
        return;
      }
      try {
        final args = call.arguments as Map<dynamic, dynamic>;
        final bytes = args['bytes'] as Uint8List;
        final width = args['width'] as int;
        final height = args['height'] as int;
        final strideRaw = args['stride'] as int;
        if (width <= 0 || height <= 0 || strideRaw <= 0) {
          return;
        }

        // 参考项目：native 上报 stride 为字节数（rowStride = width * 4）
        if (bytes.length != strideRaw * height) {
          return;
        }

        final int frameRotation = _externalFrameRotation;

        if (_externalFrameHeadLogCounter < 5) {
          _externalFrameHeadLogCounter += 1;
          _flowLog(
            'ext.frameHead',
            extra: <String, Object?>{
              'index': _externalFrameHeadLogCounter,
              'bytes': bytes.length,
              'width': width,
              'height': height,
              'expectedBytes': strideRaw * height,
              'strideRaw': strideRaw,
              'pixelFormat': 'BGRA',
              'ratio': width > 0 && height > 0
                  ? (width / height).toStringAsFixed(4)
                  : 'invalid',
              'rotation': frameRotation,
            },
          );
        }

        // 采样外部帧亮度，用于定位“已解码但黑屏”是否来自发送黑帧。
        _externalFrameLogCounter += 1;
        if (_externalFrameLogCounter % 30 == 0) {
          var acc = 0;
          var cnt = 0;
          // BGRA，每 16 像素采样一次，控制开销。
          for (var i = 0; i + 2 < bytes.length && cnt < 2000; i += 16 * 4) {
            final b = bytes[i];
            final g = bytes[i + 1];
            final r = bytes[i + 2];
            acc += (r + g + b) ~/ 3;
            cnt += 1;
          }
          if (cnt > 0) {
            final luma = acc ~/ cnt;
            if (luma <= 6) {
              _externalBlackFrameCounter += 1;
            } else {
              _externalBlackFrameCounter = 0;
            }
            // 统一在 flutter log 输出，便于你直接从日志判断发送内容是否为黑帧。
            _flowLog(
              'ext.frameSample',
              extra: <String, Object?>{
                'luma': luma,
                'blackSeq': _externalBlackFrameCounter,
                'width': width,
                'height': height,
                'ratio': width > 0 && height > 0
                    ? (width / height).toStringAsFixed(4)
                    : 'invalid',
                'strideRaw': strideRaw,
              },
            );
          }
        }

        try {
          await _engine?.getMediaEngine().pushVideoFrame(
            frame: ExternalVideoFrame(
              type: VideoBufferType.videoBufferRawData,
              format: VideoPixelFormat.videoPixelBgra,
              buffer: bytes,
              stride: width,
              height: height,
              rotation: frameRotation,
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          );
          _externalPushOkCounter += 1;
          if (_externalPushOkCounter <= 5 ||
              _externalPushOkCounter % 120 == 0) {
            _flowLog(
              'ext.pushVideoFrameOk',
              extra: <String, Object?>{
                'count': _externalPushOkCounter,
                'width': width,
                'height': height,
                'stride': width,
                'rotation': frameRotation,
              },
            );
          }
        } catch (e) {
          _externalFrameWarnCounter += 1;
          if (_externalFrameWarnCounter <= 5 ||
              _externalFrameWarnCounter % 30 == 0) {
            _flowLog(
              'ext.pushVideoFrameFailed',
              extra: <String, Object?>{'error': e.toString()},
            );
          }
        }
      } catch (e) {
        _externalFrameWarnCounter += 1;
        if (_externalFrameWarnCounter <= 5 ||
            _externalFrameWarnCounter % 30 == 0) {
          _flowLog(
            'ext.onFrameHandleFailed',
            extra: <String, Object?>{'error': e.toString()},
          );
        }
      }
    }
  }

  void _startNativePush() {
    if (_nativePushStarted) {
      _flowLog('native.startAgoraPush.skipAlreadyStarted');
      return;
    }
    _nativePushStarted = true;
    _flowLog('native.startAgoraPush.invoke');
    _beautyChannel.invokeMethod('startAgoraPush').catchError((e) {
      _nativePushStarted = false;
      _flowLog(
        'native.startAgoraPush.failed',
        extra: <String, Object?>{'error': e.toString()},
      );
    });
  }

  void _stopNativePush() {
    if (!_nativePushStarted) {
      _flowLog('native.stopAgoraPush.skipAlreadyStopped');
      return;
    }
    _nativePushStarted = false;
    _flowLog('native.stopAgoraPush.invoke');
    _beautyChannel.invokeMethod('stopAgoraPush').catchError((e) {
      _flowLog(
        'native.stopAgoraPush.failed',
        extra: <String, Object?>{'error': e.toString()},
      );
    });
  }

  Future<void> _switchNativeCamera() async {
    _flowLog('native.switchCamera.invoke');
    try {
      await _beautyChannel.invokeMethod('switchCamera');
      _flowLog('native.switchCamera.ack');
    } catch (e) {
      _flowLog(
        'native.switchCamera.failed',
        extra: <String, Object?>{'error': e.toString()},
      );
    }
  }

  Future<void> initRtc({
    required void Function() onCallConnected,
    required void Function(String endReason) onRemoteEnd,
    void Function(String message)? onLog,
    String? faceBeautyKey,
  }) async {
    final initStartAt = DateTime.now();
    if (state.isJoining || state.isJoined) {
      onLog?.call(
        'rtc init skipped: joining=${state.isJoining}, joined=${state.isJoined}',
      );
      return;
    }
    _joinedCallbackEmitted = false;
    _applyCameraFacing(true);
    state = state.copyWith(
      isJoining: true,
      isLoading: true,
      errorMessage: null,
    );
    onLog?.call('rtc init start');

    // 设置原生回调
    _beautyChannel.setMethodCallHandler(_handleNativeMethod);

    try {
      final permissionGranted = await _ensureMediaPermissions();
      if (!permissionGranted) {
        state = state.copyWith(
          isJoining: false,
          isLoading: false,
          errorMessage: '请先在系统设置中开启相机和麦克风权限',
        );
        onLog?.call('rtc init aborted: permissions not granted');
        return;
      }

      await leaveAndRelease(onLog: onLog);

      final rtcRes = await DioClient.instance.apiPost(
        ApiEndpoints.rtcToken,
        data: {'call_id': callId},
      );
      final rtcData = rtcRes['data'] as Map<String, dynamic>?;
      final appId = (rtcData?['app_id'] as String?)?.trim() ?? '';
      final channel = (rtcData?['channel'] as String?)?.trim() ?? '';
      final token = (rtcData?['token'] as String?)?.trim() ?? '';
      final uid = (rtcData?['uid'] as num?)?.toInt() ?? 0;
      onLog?.call(
        'rtc token ready: appIdLen=${appId.length}, channel=$channel, uid=$uid, tokenLen=${token.length}',
      );

      if (appId.isEmpty || channel.isEmpty || token.isEmpty || uid <= 0) {
        throw Exception('RTC 参数不完整');
      }

      // 初始化 FaceBeauty SDK
      if (faceBeautyKey != null && faceBeautyKey.isNotEmpty) {
        final beautyInitAt = DateTime.now();
        try {
          MtPlugin.initSdk(faceBeautyKey);
          onLog?.call(
            'faceBeauty init done in ${DateTime.now().difference(beautyInitAt).inMilliseconds}ms',
          );
        } catch (e) {
          onLog?.call('FaceBeauty SDK init failed: $e');
        }
      } else {
        onLog?.call('faceBeauty key missing, skip sdk init');
      }

      final engine = createAgoraRtcEngine();
      _engine = engine;
      state = state.copyWith(channelName: channel, errorMessage: null);

      final joinCompleter = Completer<void>();

      await engine.initialize(
        RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
      onLog?.call('agora engine initialized');

      // 启用外部视频源模式（FaceBeauty 原生相机采集 + 美颜处理）
      await engine.getMediaEngine().setExternalVideoSource(
        enabled: true,
        useTexture: false,
      );
      onLog?.call('external video source enabled');

      void markJoined(int localUid) {
        if (!mounted) {
          return;
        }
        final nextState = state.copyWith(
          isJoined: true,
          isJoining: false,
          isLoading: false,
          localUid: localUid,
          errorMessage: null,
        );
        state = nextState;
        if (!_joinedCallbackEmitted) {
          _joinedCallbackEmitted = true;
          onCallConnected();
          // 加入频道成功后再通知原生开始相机采集 + 美颜推流
          _startNativePush();
        }
      }

      _rtcEventHandler = RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          if (!joinCompleter.isCompleted) {
            joinCompleter.complete();
          }
          onLog?.call(
            'join success, localUid=${connection.localUid}, elapsed=$elapsed',
          );
          markJoined(connection.localUid ?? uid);
        },
        onConnectionStateChanged:
            (
              RtcConnection connection,
              ConnectionStateType connectionState,
              ConnectionChangedReasonType reason,
            ) {
              onLog?.call(
                'connection state changed: state=$connectionState, reason=$reason',
              );
              if (connectionState ==
                  ConnectionStateType.connectionStateConnected) {
                markJoined(uid);
              }
            },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          if (!mounted) {
            return;
          }
          state = state.copyWith(remoteUid: remoteUid);
          onLog?.call('remote joined, uid=$remoteUid');
        },
        onUserMuteVideo: (RtcConnection connection, int remoteUid, bool muted) {
          onLog?.call('remote mute video: uid=$remoteUid, muted=$muted');
        },
        onRemoteVideoStateChanged:
            (
              RtcConnection connection,
              int remoteUid,
              RemoteVideoState state,
              RemoteVideoStateReason reason,
              int elapsed,
            ) {
              onLog?.call(
                'remote video state: uid=$remoteUid, state=$state, reason=$reason, elapsed=$elapsed',
              );
            },
        onFirstRemoteVideoDecoded:
            (
              RtcConnection connection,
              int uid,
              int width,
              int height,
              int elapsed,
            ) {
              onLog?.call(
                'first remote video decoded: uid=$uid size=${width}x$height elapsed=$elapsed',
              );
            },
        onFirstRemoteVideoFrame:
            (
              RtcConnection connection,
              int uid,
              int width,
              int height,
              int elapsed,
            ) {
              onLog?.call(
                'first remote video frame: uid=$uid size=${width}x$height elapsed=$elapsed',
              );
            },
        onVideoSizeChanged:
            (
              RtcConnection connection,
              VideoSourceType sourceType,
              int sourceUid,
              int width,
              int height,
              int rotation,
            ) {
              onLog?.call(
                'video size changed: sourceType=$sourceType uid=$sourceUid '
                'size=${width}x$height rotation=$rotation',
              );
            },
        onUserOffline:
            (
              RtcConnection connection,
              int remoteUid,
              UserOfflineReasonType reason,
            ) {
              if (!mounted) {
                return;
              }
              if (state.remoteUid != remoteUid) {
                return;
              }
              state = state.copyWith(remoteUid: null, hasPeerLeft: true);
              onLog?.call('remote offline, immediately ending call');
              onRemoteEnd('peer_left');
            },
        onLocalVideoStateChanged:
            (
              VideoSourceType source,
              LocalVideoStreamState localVideoState,
              LocalVideoStreamReason reason,
            ) {
              if (!mounted) {
                return;
              }
              if (reason ==
                  LocalVideoStreamReason
                      .localVideoStreamReasonDeviceNoPermission) {
                state = state.copyWith(errorMessage: '相机权限不足，请在系统设置中开启后重试');
                return;
              }
              if (reason ==
                  LocalVideoStreamReason.localVideoStreamReasonDeviceBusy) {
                state = state.copyWith(errorMessage: '相机被其他应用占用，请关闭占用后重试');
                return;
              }
              if (reason ==
                  LocalVideoStreamReason.localVideoStreamReasonCaptureFailure) {
                state = state.copyWith(errorMessage: '相机采集失败，请重试或切换网络后再试');
                return;
              }
            },
        onError: (ErrorCodeType err, String msg) {
          if (!mounted) {
            return;
          }
          onLog?.call('rtc error: code=$err, msg=$msg');
          state = state.copyWith(errorMessage: 'RTC 错误: $msg');
        },
        onPermissionError: (permissionType) {
          if (!mounted) {
            return;
          }
          final isCamera = permissionType == PermissionType.camera;
          state = state.copyWith(
            errorMessage: isCamera
                ? '相机权限被拒绝，请在系统设置中开启后重试'
                : '麦克风权限被拒绝，请在系统设置中开启后重试',
          );
        },
        onLocalAudioStateChanged: (connection, localAudioState, reason) {
          if (!mounted) {
            return;
          }
          if (reason ==
              LocalAudioStreamReason.localAudioStreamReasonDeviceNoPermission) {
            state = state.copyWith(errorMessage: '麦克风权限不足，请在系统设置中开启后重试');
            return;
          }
          if (reason ==
              LocalAudioStreamReason.localAudioStreamReasonDeviceBusy) {
            state = state.copyWith(errorMessage: '麦克风被其他应用占用，请关闭占用后重试');
            return;
          }
        },
      );
      engine.registerEventHandler(_rtcEventHandler!);

      await engine.enableVideo();
      await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      onLog?.call('enableVideo + setClientRole done');
      // 移除 startPreview()，改为使用原生相机采集
      // await engine.startPreview();

      Future<void> doJoin() async {
        await engine.joinChannel(
          token: token,
          channelId: channel,
          uid: uid,
          options: const ChannelMediaOptions(
            channelProfile: ChannelProfileType.channelProfileCommunication,
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
            // 外部视频源模式下，不发布内置摄像头轨道
            publishCameraTrack: false,
            // 外部源帧通过 pushVideoFrame(trackId=0) 推送，需要发布自定义视频轨。
            publishCustomVideoTrack: true,
            customVideoTrackId: 0,
            publishMicrophoneTrack: true,
            autoSubscribeAudio: true,
            autoSubscribeVideo: true,
          ),
        );
      }

      Future<bool> isJoinRejected(Object error) async {
        if (error is AgoraRtcException) {
          return error.code == -17 || error.code == 17;
        }
        final text = error.toString();
        return text.contains('-17') || text.contains('17');
      }

      try {
        await doJoin();
        onLog?.call('joinChannel called');
      } catch (e) {
        if (await isJoinRejected(e)) {
          onLog?.call('join rejected(-17), retry once');
          await engine.leaveChannel();
          await Future.delayed(const Duration(milliseconds: 300));
          await doJoin();
        } else {
          rethrow;
        }
      }

      if (!joinCompleter.isCompleted) {
        try {
          await joinCompleter.future.timeout(const Duration(seconds: 5));
        } catch (_) {
          state = state.copyWith(
            isJoining: false,
            isLoading: false,
            errorMessage: '连接中，请稍候...',
          );
          return;
        }
      }

      state = state.copyWith(isJoining: false, isLoading: false);
      onLog?.call(
        'rtc init finished in ${DateTime.now().difference(initStartAt).inMilliseconds}ms',
      );
    } catch (e) {
      onLog?.call('rtc init failed: $e');
      state = state.copyWith(
        isJoining: false,
        isLoading: false,
        errorMessage: '视频通话初始化失败，请稍后重试',
      );
    }
  }

  Future<void> leaveAndRelease({void Function(String message)? onLog}) async {
    // 离开前先停止原生推流
    _stopNativePush();

    final engine = _engine;
    _engine = null;
    _joinedCallbackEmitted = false;
    _nativePushStarted = false;

    if (engine != null) {
      onLog?.call('rtc release start');
      try {
        if (_rtcEventHandler != null) {
          engine.unregisterEventHandler(_rtcEventHandler!);
        }
      } catch (_) {}
      _rtcEventHandler = null;
      try {
        await engine.leaveChannel();
      } catch (_) {}
      try {
        await engine.release();
      } catch (_) {}
      onLog?.call('rtc release end');
    }

    if (!mounted) {
      return;
    }
    state = state.copyWith(
      isLoading: false,
      isJoining: false,
      isJoined: false,
      hasPeerLeft: false,
      localUid: null,
      remoteUid: null,
      channelName: null,
    );
  }

  Future<void> toggleMic() async {
    final next = !state.isMicOn;
    try {
      await _engine?.muteLocalAudioStream(!next);
    } catch (_) {}
    if (!mounted) {
      return;
    }
    state = state.copyWith(isMicOn: next);
  }

  Future<void> toggleSpeaker() async {
    final next = !state.isSpeakerOn;
    try {
      await _engine?.setEnableSpeakerphone(next);
    } catch (_) {}
    if (!mounted) {
      return;
    }
    state = state.copyWith(isSpeakerOn: next);
  }

  Future<void> toggleCamera() async {
    final next = !state.isCameraOn;
    _flowLog('ui.toggleCamera', extra: <String, Object?>{'next': next});
    try {
      if (next) {
        await _beautyChannel.invokeMethod('startAgoraPush');
        _nativePushStarted = true;
      } else {
        await _beautyChannel.invokeMethod('stopAgoraPush');
        _nativePushStarted = false;
      }
      _flowLog(
        'ui.toggleCamera.nativeAck',
        extra: <String, Object?>{'next': next},
      );
    } catch (e) {
      _flowLog(
        'ui.toggleCamera.nativeFailed',
        extra: <String, Object?>{'next': next, 'error': e.toString()},
      );
    }
    if (!mounted) {
      return;
    }
    state = state.copyWith(isCameraOn: next);
    _flowLog(
      'ui.toggleCamera.stateUpdated',
      extra: <String, Object?>{'next': next},
    );
  }

  Future<void> flipCamera() async {
    _flowLog('ui.flipCamera.start');
    state = state.copyWith(isFlipping: true);
    final predictedNextIsFrontCamera = !_isFrontCamera;
    _flowLog(
      'ui.flipCamera.rotationPredicted',
      extra: <String, Object?>{
        'from': _isFrontCamera ? 'front' : 'back',
        'to': predictedNextIsFrontCamera ? 'front' : 'back',
        'rotation': _rotationForCamera(predictedNextIsFrontCamera),
      },
    );
    _dropFramesDuringCameraSwitch = true;
    _cameraSwitchDropGuardTimer?.cancel();
    _cameraSwitchDropGuardTimer = Timer(const Duration(seconds: 2), () {
      _dropFramesDuringCameraSwitch = false;
      _cameraSwitchDropGuardTimer = null;
      _cameraSwitchResumePushTimer?.cancel();
      _cameraSwitchResumePushTimer = null;
      if (state.isJoined && state.isCameraOn) {
        _startNativePush();
      }
      if (state.isFlipping) {
        _finishFlipTransition(delay: Duration.zero);
      }
      _flowLog('ui.flipCamera.dropGuardTimeout');
    });
    try {
      final shouldPausePush = state.isCameraOn && state.isJoined;
      if (shouldPausePush) {
        _stopNativePush();
      }
      await _switchNativeCamera();
      // 切镜头后由 native 回调（cameraSwitchResult/previewReady）统一恢复推流，
      // 避免在旋转状态尚未更新前提前推送，导致短暂倒置。
    } catch (e) {
      _flowLog(
        'ui.flipCamera.error',
        extra: <String, Object?>{
          'error': e.toString(),
          'current': _isFrontCamera ? 'front' : 'back',
          'rotation': _externalFrameRotation,
        },
      );
      _cameraSwitchDropGuardTimer?.cancel();
      _cameraSwitchDropGuardTimer = null;
      _dropFramesDuringCameraSwitch = false;
      if (mounted) {
        state = state.copyWith(isFlipping: false);
        _flowLog('ui.flipCamera.end');
      }
    }
  }

  Future<bool> _ensureMediaPermissions() async {
    final statuses = await [Permission.camera, Permission.microphone].request();
    final cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
    final micGranted = statuses[Permission.microphone]?.isGranted ?? false;
    return cameraGranted && micGranted;
  }

  @override
  void dispose() {
    _cameraSwitchDropGuardTimer?.cancel();
    _cameraSwitchDropGuardTimer = null;
    _cameraSwitchResumePushTimer?.cancel();
    _cameraSwitchResumePushTimer = null;
    _flipUiGuardTimer?.cancel();
    _flipUiGuardTimer = null;
    unawaited(leaveAndRelease());
    _beautyChannel.setMethodCallHandler(null);
    super.dispose();
  }
}

final callRtcControllerProvider = StateNotifierProvider.autoDispose
    .family<CallRtcController, CallRtcState, int>(
      (ref, callId) => CallRtcController(callId: callId),
    );
