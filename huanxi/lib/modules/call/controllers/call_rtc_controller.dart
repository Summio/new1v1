import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/app_logger.dart';

const _rtcNoValue = Object();

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
  int _logSeq = 0;

  RtcEngine? get engine => _engine;

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
    }..addAll(extra);
    AppLogger.debugJson('[CALL_FLOW][callId=$callId]', snapshot);
  }

  Future<void> initRtc({
    required void Function() onCallConnected,
    required void Function(String endReason) onRemoteEnd,
    void Function(String message)? onLog,
  }) async {
    final initStartAt = DateTime.now();
    if (state.isJoining || state.isJoined) {
      onLog?.call(
        'rtc init skipped: joining=${state.isJoining}, joined=${state.isJoined}',
      );
      return;
    }
    _joinedCallbackEmitted = false;
    state = state.copyWith(
      isJoining: true,
      isLoading: true,
      errorMessage: null,
    );
    onLog?.call('rtc init start');

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

      // 启用 Agora 内置视频预览
      await engine.startPreview();
      onLog?.call('startPreview done');

      Future<void> doJoin() async {
        await engine.joinChannel(
          token: token,
          channelId: channel,
          uid: uid,
          options: const ChannelMediaOptions(
            channelProfile: ChannelProfileType.channelProfileCommunication,
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
            publishCameraTrack: true,
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
      await _engine?.muteLocalVideoStream(!next);
    } catch (e) {
      _flowLog('toggleCamera failed', extra: {'error': e.toString()});
    }
    if (!mounted) {
      return;
    }
    state = state.copyWith(isCameraOn: next);
  }

  Future<void> flipCamera() async {
    _flowLog('ui.flipCamera.start');
    state = state.copyWith(isFlipping: true);
    final predictedNextIsFrontCamera = !state.isFrontCamera;
    try {
      await _engine?.switchCamera();
      if (!mounted) {
        return;
      }
      state = state.copyWith(isFlipping: false, isFrontCamera: predictedNextIsFrontCamera);
      _flowLog(
        'ui.flipCamera.done',
        extra: {'next': predictedNextIsFrontCamera ? 'front' : 'back'},
      );
    } catch (e) {
      _flowLog(
        'ui.flipCamera.error',
        extra: {'error': e.toString()},
      );
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
    super.dispose();
  }
}

final callRtcControllerProvider = StateNotifierProvider.autoDispose
    .family<CallRtcController, CallRtcState, int>(
      (ref, callId) => CallRtcController(callId: callId),
    );
