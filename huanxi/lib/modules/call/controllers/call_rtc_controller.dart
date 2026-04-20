import 'dart:async';
import 'dart:typed_data';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mt_plugin/mt_plugin.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/providers/auth_provider.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';

const _rtcNoValue = Object();

class CallRtcState {
  final bool isMicOn;
  final bool isSpeakerOn;
  final bool isCameraOn;
  final bool isFlipping;
  final bool isLoading;
  final bool isJoining;
  final bool isJoined;
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
      localUid: identical(localUid, _rtcNoValue) ? this.localUid : localUid as int?,
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

  // MethodChannel 用于与原生 FaceBeauty 通信
  static const MethodChannel _beautyChannel = MethodChannel('beauty_plugin');

  RtcEngine? get engine => _engine;

  Future<dynamic> _handleNativeMethod(MethodCall call) async {
    if (call.method == 'onFrame') {
      try {
        final args = call.arguments as Map<dynamic, dynamic>;
        final bytes = args['bytes'] as Uint8List;
        final width = args['width'] as int;
        final height = args['height'] as int;
        final stride = args['stride'] as int;

        if (bytes.length != stride * height) {
          return;
        }

        await _engine?.getMediaEngine().pushVideoFrame(
          frame: ExternalVideoFrame(
            type: VideoBufferType.videoBufferRawData,
            format: VideoPixelFormat.videoPixelBgra,
            buffer: bytes,
            stride: width,
            height: height,
            rotation: 180,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      } catch (_) {
        // 忽略帧推送错误，避免影响通话
      }
    }
  }

  void _startNativePush() {
    _beautyChannel.invokeMethod('startAgoraPush').catchError((_) {});
  }

  void _stopNativePush() {
    _beautyChannel.invokeMethod('stopAgoraPush').catchError((_) {});
  }

  void _switchNativeCamera() {
    _beautyChannel.invokeMethod('switchCamera').catchError((_) {});
  }

  Future<void> initRtc({
    required void Function() onCallConnected,
    required void Function(String endReason) onRemoteEnd,
    void Function(String message)? onLog,
    String? faceBeautyKey,
  }) async {
    if (state.isJoining || state.isJoined) {
      return;
    }
    _joinedCallbackEmitted = false;
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

      if (appId.isEmpty || channel.isEmpty || token.isEmpty || uid <= 0) {
        throw Exception('RTC 参数不完整');
      }

      // 初始化 FaceBeauty SDK
      if (faceBeautyKey != null && faceBeautyKey.isNotEmpty) {
        try {
          MtPlugin.initSdk(faceBeautyKey);
        } catch (e) {
          onLog?.call('FaceBeauty SDK init failed: $e');
        }
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

      // 启用外部视频源模式（FaceBeauty 原生相机采集 + 美颜处理）
      await engine.getMediaEngine().setExternalVideoSource(
        enabled: true,
        useTexture: false,
      );

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
        onConnectionStateChanged: (
          RtcConnection connection,
          ConnectionStateType connectionState,
          ConnectionChangedReasonType reason,
        ) {
          onLog?.call(
            'connection state changed: state=$connectionState, reason=$reason',
          );
          if (connectionState == ConnectionStateType.connectionStateConnected) {
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
        onUserOffline: (
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
        onLocalVideoStateChanged: (
          VideoSourceType source,
          LocalVideoStreamState localVideoState,
          LocalVideoStreamReason reason,
        ) {
          if (!mounted) {
            return;
          }
          if (reason ==
              LocalVideoStreamReason.localVideoStreamReasonDeviceNoPermission) {
            state = state.copyWith(errorMessage: '相机权限不足，请在系统设置中开启后重试');
            return;
          }
          if (reason == LocalVideoStreamReason.localVideoStreamReasonDeviceBusy) {
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
          if (reason == LocalAudioStreamReason.localAudioStreamReasonDeviceBusy) {
            state = state.copyWith(errorMessage: '麦克风被其他应用占用，请关闭占用后重试');
            return;
          }
        },
      );
      engine.registerEventHandler(_rtcEventHandler!);

      await engine.enableVideo();
      await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
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
    try {
      if (next) {
        _beautyChannel.invokeMethod('startAgoraPush');
      } else {
        _beautyChannel.invokeMethod('stopAgoraPush');
      }
    } catch (_) {}
    if (!mounted) {
      return;
    }
    state = state.copyWith(isCameraOn: next);
  }

  Future<void> flipCamera() async {
    state = state.copyWith(isFlipping: true);
    try {
      _switchNativeCamera();
    } catch (_) {
    } finally {
      if (mounted) {
        state = state.copyWith(isFlipping: false);
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
    unawaited(leaveAndRelease());
    _beautyChannel.setMethodCallHandler(null);
    super.dispose();
  }
}

final callRtcControllerProvider =
    StateNotifierProvider.autoDispose.family<CallRtcController, CallRtcState, int>(
      (ref, callId) => CallRtcController(callId: callId),
    );
