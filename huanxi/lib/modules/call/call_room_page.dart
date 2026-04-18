import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/providers/anchor_provider.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/app_toast.dart';
import '../../services/websocket_service.dart';
import '../gift/gift_panel.dart';

/// 通话房间页面
/// 基于声网 RTC 实现实时视频通话
class CallRoomPage extends ConsumerStatefulWidget {
  final int callId;

  /// 通话对端 AppUser ID（用于资料展示）
  final String peerUserId;

  /// 礼物目标 Anchor ID（可选，缺省时尝试按 peerUserId 反查）
  final String? anchorId;
  final String peerName;

  const CallRoomPage({
    super.key,
    required this.callId,
    required this.peerUserId,
    this.anchorId,
    this.peerName = '',
  });

  @override
  ConsumerState<CallRoomPage> createState() => _CallRoomPageState();
}

class _CallRoomPageState extends ConsumerState<CallRoomPage> {
  static const Duration _wsGracePeriod = Duration(seconds: 10);
  RtcEngine? _engine;
  RtcEngineEventHandler? _rtcEventHandler;
  Timer? _durationTimer;
  Timer? _wsDisconnectTimer;
  StreamSubscription<WsEvent>? _wsSubscription;
  StreamSubscription<WsConnectionEvent>? _wsConnectionSubscription;

  // 礼物动画状态
  bool _giftShowing = false;
  String _giftName = '';
  String _giftIcon = '';
  int _giftPrice = 0;
  String _giftSenderNickname = '';

  bool _isMicOn = true;
  bool _isSpeakerOn = true;
  bool _isCameraOn = true;
  bool _isFlipping = false;
  bool _isLoading = true;
  bool _joined = false;
  bool _hasEnded = false;
  bool _endingInProgress = false;
  bool _rtcJoining = false;
  bool _endingForBalance = false;

  int? _localUid;
  int? _remoteUid;
  String? _channelName;
  String? _errorMessage;

  Duration _callDuration = Duration.zero;
  DateTime? _callStartTime;

  void _log(String message) {
    debugPrint('[CALL_FLOW][callId=${widget.callId}] $message');
  }

  @override
  void initState() {
    super.initState();
    _log(
      'page init, peerUserId=${widget.peerUserId}, '
      'anchorId=${widget.anchorId}, peerName=${widget.peerName}',
    );
    _initWebSocket();
    unawaited(_initRtc());
  }

  void _initWebSocket() {
    WsService.instance.connect();
    _wsSubscription?.cancel();
    _wsSubscription = WsService.instance.events.listen(_onWsEvent);
    _wsConnectionSubscription?.cancel();
    _wsConnectionSubscription = WsService.instance.connectionEvents.listen(
      _onWsConnectionEvent,
    );
  }

  void _onWsConnectionEvent(WsConnectionEvent event) {
    if (!mounted || _hasEnded) return;

    if (event.state == WsConnectionState.connected) {
      _wsDisconnectTimer?.cancel();
      _wsDisconnectTimer = null;
      return;
    }

    if (event.state == WsConnectionState.reconnecting ||
        event.state == WsConnectionState.disconnected ||
        event.state == WsConnectionState.authFailed) {
      _wsDisconnectTimer ??= Timer(_wsGracePeriod, () {
        if (!mounted || _hasEnded || WsService.instance.isConnected) return;
        _handleEndedByRemote('network_lost');
      });
    }
  }

  void _onWsEvent(WsEvent event) {
    if (event.event == 'call_balance_empty') {
      final callId = event.data['call_id'] as int?;
      if (callId != widget.callId || _hasEnded) return;
      unawaited(_handleBalanceEmptyEnded());
      return;
    }

    // 通话结束类事件：call_ended, call_cancelled, call_timeout, call_rejected
    final callEndedEvents = {
      'call_ended',
      'call_cancelled',
      'call_timeout',
      'call_rejected',
    };
    if (callEndedEvents.contains(event.event)) {
      final callId = event.data['call_id'] as int?;
      if (callId != widget.callId) return;
      if (_hasEnded) return;
      _handleEndedByRemote(event.data['end_reason'] as String?);
    } else if (event.event == 'balance_updated') {
      final coins = event.data['coins'] as int?;
      final diamonds = event.data['diamonds'] as int?;
      if (coins != null || diamonds != null) {
        ref
            .read(authProvider.notifier)
            .syncBalance(coins: coins, diamonds: diamonds);
      }
    } else if (event.event == 'gift_received') {
      _showGiftAnimation(
        giftName: event.data['gift_name'] as String? ?? '',
        giftIcon: event.data['gift_icon'] as String? ?? '',
        giftPrice: event.data['gift_price'] as int? ?? 0,
        senderNickname: event.data['sender_nickname'] as String? ?? '用户',
      );
    }
  }

  Future<void> _initRtc() async {
    if (_rtcJoining || _joined || _hasEnded) return;
    _rtcJoining = true;
    _log('rtc init start');

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final permissionGranted = await _ensureMediaPermissions();
      if (!permissionGranted) {
        _log('rtc init aborted: permissions not granted');
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = '请先在系统设置中开启相机和麦克风权限';
        });
        return;
      }

      // 防御性处理：清理潜在残留 RTC 状态
      await _releaseRtcEngine();

      final rtcRes = await DioClient.instance.apiPost(
        ApiEndpoints.rtcToken,
        data: {'call_id': widget.callId},
      );
      final rtcData = rtcRes['data'] as Map<String, dynamic>?;
      final appId = (rtcData?['app_id'] as String?)?.trim() ?? '';
      final channel = (rtcData?['channel'] as String?)?.trim() ?? '';
      final token = (rtcData?['token'] as String?)?.trim() ?? '';
      final uid = (rtcData?['uid'] as num?)?.toInt() ?? 0;

      if (appId.isEmpty || channel.isEmpty || token.isEmpty || uid <= 0) {
        _log('rtc init failed: invalid rtc params');
        throw Exception('RTC 参数不完整');
      }
      _log('rtc token ready, channel=$channel uid=$uid');

      final engine = createAgoraRtcEngine();
      _engine = engine;
      _channelName = channel;
      final joinCompleter = Completer<void>();

      await engine.initialize(
        RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      _rtcEventHandler = RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          if (!mounted) return;
          _log(
            'join success, localUid=${connection.localUid}, elapsed=$elapsed',
          );
          if (!joinCompleter.isCompleted) {
            joinCompleter.complete();
          }
          setState(() {
            _joined = true;
            _localUid = connection.localUid;
          });
          _startDurationTimer();
        },
        onConnectionStateChanged:
            (
              RtcConnection connection,
              ConnectionStateType state,
              ConnectionChangedReasonType reason,
            ) {
              _log('connection state changed: state=$state, reason=$reason');
              if (!mounted) return;
              if (state == ConnectionStateType.connectionStateConnected &&
                  !_joined) {
                _log('fallback mark joined by connection state');
                setState(() {
                  _joined = true;
                  _localUid = uid;
                });
                _startDurationTimer();
              }
            },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          if (!mounted) return;
          _log('remote joined, uid=$remoteUid');
          setState(() => _remoteUid = remoteUid);
        },
        onFirstRemoteVideoFrame:
            (
              RtcConnection connection,
              int remoteUid,
              int width,
              int height,
              int elapsed,
            ) {
              _log(
                'first remote video frame, uid=$remoteUid, ${width}x$height, elapsed=$elapsed',
              );
            },
        onRemoteVideoStateChanged:
            (
              RtcConnection connection,
              int remoteUid,
              RemoteVideoState state,
              RemoteVideoStateReason reason,
              int elapsed,
            ) {
              _log(
                'remote video state, uid=$remoteUid, state=$state, reason=$reason, elapsed=$elapsed',
              );
            },
        onLocalVideoStateChanged:
            (
              VideoSourceType source,
              LocalVideoStreamState state,
              LocalVideoStreamReason reason,
            ) {
              _log(
                'local video state, source=$source, state=$state, reason=$reason',
              );
              if (!mounted) return;
              if (reason ==
                  LocalVideoStreamReason
                      .localVideoStreamReasonDeviceNoPermission) {
                setState(() => _errorMessage = '相机权限不足，请在系统设置中开启后重试');
                return;
              }
              if (reason ==
                  LocalVideoStreamReason.localVideoStreamReasonDeviceBusy) {
                setState(() => _errorMessage = '相机被其他应用占用，请关闭占用后重试');
                return;
              }
              if (reason ==
                  LocalVideoStreamReason.localVideoStreamReasonCaptureFailure) {
                setState(() => _errorMessage = '相机采集失败，请重试或切换网络后再试');
                return;
              }
            },
        onUserOffline:
            (
              RtcConnection connection,
              int remoteUid,
              UserOfflineReasonType reason,
            ) {
              if (!mounted) return;
              if (_remoteUid == remoteUid) {
                _log('remote offline, uid=$remoteUid, reason=$reason');
                setState(() => _remoteUid = null);
              }
            },
        onError: (ErrorCodeType err, String msg) {
          if (!mounted) return;
          _log('rtc error: code=$err msg=$msg');
          setState(() => _errorMessage = 'RTC 错误: $msg');
        },
        onPermissionError: (permissionType) {
          if (!mounted) return;
          final isCamera = permissionType == PermissionType.camera;
          setState(() {
            _errorMessage = isCamera
                ? '相机权限被拒绝，请在系统设置中开启后重试'
                : '麦克风权限被拒绝，请在系统设置中开启后重试';
          });
          _log('permission error: type=$permissionType');
        },
        onLocalAudioStateChanged: (connection, state, reason) {
          if (!mounted) return;
          if (reason ==
              LocalAudioStreamReason.localAudioStreamReasonDeviceNoPermission) {
            _log('local audio state: no permission');
            setState(() => _errorMessage = '麦克风权限不足，请在系统设置中开启后重试');
            return;
          }
          if (reason ==
              LocalAudioStreamReason.localAudioStreamReasonDeviceBusy) {
            _log('local audio state: device busy');
            setState(() => _errorMessage = '麦克风被其他应用占用，请关闭占用后重试');
            return;
          }
        },
      );
      engine.registerEventHandler(_rtcEventHandler!);

      await engine.enableVideo();
      await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await engine.startPreview();

      Future<void> doJoin() async {
        _log('join start, channel=$channel uid=$uid');
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
        _log('join api returned');
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
        // 对 -17 做一次快速重试
        if (await isJoinRejected(e)) {
          _log('join rejected(-17), retry once');
          await engine.leaveChannel();
          await Future.delayed(const Duration(milliseconds: 300));
          await doJoin();
        } else {
          _log('join failed, error=$e');
          rethrow;
        }
      }

      // 等待 join success 回调；若超时不主动重建，避免进入反复 release/rejoin 循环
      if (!joinCompleter.isCompleted) {
        try {
          await joinCompleter.future.timeout(const Duration(seconds: 5));
        } catch (_) {
          _log(
            'join success callback timeout, keep waiting for connection state',
          );
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = '连接中，请稍候...';
            });
          }
          return;
        }
      }

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      _log('rtc init failed: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '视频通话初始化失败，请稍后重试';
      });
    } finally {
      _rtcJoining = false;
      _log('rtc init end');
    }
  }

  Future<bool> _ensureMediaPermissions() async {
    final statuses = await [Permission.camera, Permission.microphone].request();

    final cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
    final micGranted = statuses[Permission.microphone]?.isGranted ?? false;
    return cameraGranted && micGranted;
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _callStartTime = DateTime.now();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_callStartTime != null && mounted) {
        final duration = DateTime.now().difference(_callStartTime!);
        setState(() {
          _callDuration = duration;
        });
      }
    });
  }

  Future<void> _handleBalanceEmptyEnded() async {
    if (_endingForBalance || _hasEnded || !mounted) return;
    _endingForBalance = true;
    _log('received call_balance_empty, auto exit in 3s');
    AppToast.showSnackBar(
      context,
      const SnackBar(content: Text('余额不足，通话即将结束')),
    );
    await Future.delayed(const Duration(seconds: 3));
    if (mounted && !_hasEnded) {
      await _leaveAndExit(notifyEndApi: false);
    }
  }

  Future<void> _endCall() async {
    if (_endingInProgress || _hasEnded) return;
    _endingInProgress = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认挂断'),
          content: const Text('确定要结束当前通话吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('挂断'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        _log('end call canceled by user');
        _endingInProgress = false;
        return;
      }

      _log('end call confirmed');
      await _leaveAndExit();
    } catch (_) {
      _endingInProgress = false;
      rethrow;
    }
  }

  Future<void> _handleEndedByRemote(String? endReason) async {
    if (_hasEnded) return;

    String tip = '通话已结束';
    if (endReason == 'rejected') {
      tip = '对方已拒绝';
    } else if (endReason == 'timeout') {
      tip = '无人接听，通话超时';
    } else if (endReason == 'cancelled') {
      tip = '对方已取消呼叫';
    }

    if (mounted) {
      AppToast.showSnackBar(context, SnackBar(content: Text(tip)));
    }

    await _leaveAndExit(notifyEndApi: false);
  }

  Future<void> _leaveAndExit({bool notifyEndApi = true}) async {
    if (_hasEnded) return;
    _hasEnded = true;
    _log('leave and exit start, notifyEndApi=$notifyEndApi');
    _wsDisconnectTimer?.cancel();
    _durationTimer?.cancel();

    try {
      if (notifyEndApi) {
        _log('call end api request');
        await DioClient.instance.apiPost(
          ApiEndpoints.callEnd,
          data: {'call_id': widget.callId},
        );
      }
    } catch (_) {}

    await _releaseRtcEngine();

    if (!mounted) return;
    if (context.canPop()) {
      _log('route pop');
      context.pop();
    } else {
      _log('route go index');
      context.go(AppRoutes.index);
    }
  }

  Future<void> _releaseRtcEngine() async {
    final engine = _engine;
    _engine = null;
    if (engine == null) return;
    _log('rtc release start');
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
    _log('rtc release end');
  }

  Future<void> _toggleMic() async {
    final next = !_isMicOn;
    await _engine?.muteLocalAudioStream(!next);
    if (!mounted) return;
    setState(() => _isMicOn = next);
  }

  Future<void> _toggleSpeaker() async {
    final next = !_isSpeakerOn;
    await _engine?.setEnableSpeakerphone(next);
    if (!mounted) return;
    setState(() => _isSpeakerOn = next);
  }

  Future<void> _toggleCamera() async {
    final next = !_isCameraOn;
    await _engine?.muteLocalVideoStream(!next);
    if (!mounted) return;
    setState(() => _isCameraOn = next);
  }

  Future<void> _flipCamera() async {
    setState(() => _isFlipping = true);
    try {
      await _engine?.switchCamera();
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isFlipping = false);
      }
    }
  }

  int? _resolveGiftTargetAnchorId(AnchorInfo? anchor) {
    final fromRoute = int.tryParse((widget.anchorId ?? '').trim());
    if (fromRoute != null && fromRoute > 0) {
      return fromRoute;
    }
    // 兼容：未显式传 anchorId 时，若对端在主播列表里可反查 Anchor.id。
    return anchor?.id;
  }

  void _showGiftPanel(AnchorInfo? anchor) {
    final targetAnchorId = _resolveGiftTargetAnchorId(anchor);
    if (targetAnchorId == null || targetAnchorId <= 0) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('当前通话对象非主播，暂不支持送礼')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GiftPanel(
        anchorId: targetAnchorId.toString(),
        onClose: () => Navigator.pop(context),
      ),
    );
  }

  void _showGiftAnimation({
    required String giftName,
    required String giftIcon,
    required int giftPrice,
    required String senderNickname,
  }) {
    if (!mounted) return;
    setState(() {
      _giftShowing = true;
      _giftName = giftName;
      _giftIcon = giftIcon;
      _giftPrice = giftPrice;
      _giftSenderNickname = senderNickname;
    });
    // 3秒后自动隐藏
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _giftShowing = false);
      }
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  bool _shouldBestEffortTerminateOnDispose() {
    return !_hasEnded && _joined;
  }

  @override
  void dispose() {
    final shouldTerminate = _shouldBestEffortTerminateOnDispose();
    if (shouldTerminate) {
      _log('dispose with active joined call, best effort terminate');
      unawaited(_bestEffortTerminateCall());
    } else {
      _log(
        'dispose skip best effort terminate, '
        'hasEnded=$_hasEnded joined=$_joined',
      );
    }
    _wsDisconnectTimer?.cancel();
    _durationTimer?.cancel();
    _wsSubscription?.cancel();
    _wsConnectionSubscription?.cancel();
    unawaited(_releaseRtcEngine());
    super.dispose();
  }

  Future<void> _bestEffortTerminateCall() async {
    if (_hasEnded) return;
    _hasEnded = true;
    _log('best effort terminate start');
    try {
      _log('best effort call end api request');
      await DioClient.instance.apiPost(
        ApiEndpoints.callEnd,
        data: {'call_id': widget.callId},
      );
    } catch (_) {}
    _log('best effort terminate end');
  }

  @override
  Widget build(BuildContext context) {
    final anchorState = ref.watch(anchorListProvider);
    AnchorInfo? found;
    for (final a in anchorState.anchors) {
      if (a.userId.toString() == widget.peerUserId) {
        found = a;
        break;
      }
    }
    final anchor = found;
    final peerName = widget.peerName.trim().isNotEmpty
        ? widget.peerName.trim()
        : (anchor?.username ?? '主播');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_endCall());
        }
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2D1F2F), Color(0xFF1A1A1A)],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildRemoteView(),
              if (_giftShowing) _buildGiftAnimationOverlay(),
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 16,
                child: GestureDetector(
                  onTap: _flipCamera,
                  child: AnimatedContainer(
                    duration: Duration.zero,
                    width: 90,
                    height: 120,
                    decoration: BoxDecoration(
                      color: _isCameraOn
                          ? const Color(0xFF2A2A2A)
                          : Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: _buildLocalPreview(),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 12,
                    left: 16,
                    right: 16,
                    bottom: 12,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: _endCall,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              peerName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _formatDuration(_callDuration),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (anchor?.callPrice != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '￥${anchor!.callPrice!.toStringAsFixed(0)}/min',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    bottom: MediaQuery.of(context).padding.bottom + 24,
                    top: 20,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ControlButton(
                        icon: _isMicOn ? Icons.mic : Icons.mic_off,
                        label: _isMicOn ? '麦克风' : '静音',
                        isActive: !_isMicOn,
                        onTap: () => _toggleMic(),
                      ),
                      _ControlButton(
                        icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                        label: '扬声器',
                        isActive: !_isSpeakerOn,
                        onTap: () => _toggleSpeaker(),
                      ),
                      _ControlButton(
                        icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
                        label: '摄像头',
                        isActive: !_isCameraOn,
                        onTap: () => _toggleCamera(),
                      ),
                      _ControlButton(
                        icon: Icons.card_giftcard,
                        label: '礼物',
                        onTap: () => _showGiftPanel(anchor),
                      ),
                      _ControlButton(
                        icon: Icons.flip_camera_ios,
                        label: '翻转',
                        isSpinning: _isFlipping,
                        onTap: () => _flipCamera(),
                      ),
                      GestureDetector(
                        onTap: _endCall,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: const BoxDecoration(
                            color: AppTheme.errorColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.call_end,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isLoading)
                Container(
                  color: Colors.black45,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRemoteView() {
    final engine = _engine;
    final channelName = _channelName;
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }

    if (_remoteUid != null && engine != null && channelName != null) {
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: engine,
          canvas: VideoCanvas(uid: _remoteUid),
          connection: RtcConnection(channelId: channelName),
        ),
      );
    }

    return _buildPlaceholder();
  }

  Widget _buildLocalPreview() {
    final engine = _engine;
    if (!_isCameraOn || engine == null) {
      return const Icon(Icons.videocam_off, color: Colors.white30, size: 32);
    }

    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: engine,
        canvas: const VideoCanvas(uid: 0),
      ),
    );
  }

  Widget _buildPlaceholder() {
    String statusText;
    if (_joined) {
      statusText = '等待对方加入...';
    } else {
      statusText = '正在连接视频通话...';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor.withValues(alpha: 0.2),
                  AppTheme.accentColor.withValues(alpha: 0.2),
                ],
              ),
            ),
            child: const Icon(Icons.person, size: 64, color: Colors.white24),
          ),
          const SizedBox(height: 16),
          Text(
            statusText,
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          if (_localUid != null && _channelName != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '频道: $_channelName  UID: $_localUid',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGiftAnimationOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 300),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.scale(
                  scale: 0.8 + (0.2 * value),
                  child: child,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _giftIcon.isNotEmpty
                      ? Image.network(
                          _giftIcon,
                          width: 48,
                          height: 48,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.card_giftcard,
                                color: AppTheme.secondaryColor,
                                size: 48,
                              ),
                        )
                      : const Icon(
                          Icons.card_giftcard,
                          color: AppTheme.secondaryColor,
                          size: 48,
                        ),
                  const SizedBox(width: 16),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _giftSenderNickname,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '送出了 $_giftName',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_giftPrice > 0)
                        Text(
                          '价值 ¥${_giftPrice.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppTheme.secondaryColor,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 控制按钮组件
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final bool isSpinning;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.isSpinning = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: Duration.zero,
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isActive
                  ? AppTheme.primaryColor.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: isSpinning
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
