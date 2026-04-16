import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/anchor_provider.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../gift/gift_panel.dart';

/// 通话房间页面
/// 基于声网 RTC 实现实时视频通话
class CallRoomPage extends ConsumerStatefulWidget {
  final int callId;
  final String anchorId;

  const CallRoomPage({
    super.key,
    required this.callId,
    required this.anchorId,
  });

  @override
  ConsumerState<CallRoomPage> createState() => _CallRoomPageState();
}

class _CallRoomPageState extends ConsumerState<CallRoomPage> {
  AgoraRtcEngine? _engine;
  Timer? _durationTimer;
  Timer? _statusTimer;

  bool _isMicOn = true;
  bool _isSpeakerOn = true;
  bool _isCameraOn = true;
  bool _isFlipping = false;
  bool _isLoading = true;
  bool _joined = false;
  bool _hasEnded = false;
  bool _endingInProgress = false;
  bool _rtcJoining = false;
  bool _isCaller = false;

  String _callStatus = 'pending';
  int _pendingLeftSeconds = 30;

  int? _localUid;
  int? _remoteUid;
  String? _channelName;
  String? _errorMessage;

  Duration _callDuration = Duration.zero;
  DateTime? _callStartTime;

  @override
  void initState() {
    super.initState();
    _startStatusPolling();
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkCallStatus();
    });
    _checkCallStatus();
  }

  Future<void> _checkCallStatus() async {
    if (_hasEnded) return;

    try {
      final res = await DioClient.instance.apiGet(
        ApiEndpoints.callStatus,
        params: {'call_id': widget.callId},
      );
      final data = res['data'] as Map<String, dynamic>?;
      final status = (data?['status'] as String?)?.trim() ?? 'ended';
      final endReason = (data?['end_reason'] as String?)?.trim();
      final callerId = (data?['caller_id'] as num?)?.toInt();
      final createdAtRaw = (data?['created_at'] as String?)?.trim();
      final myUserId = ref.read(authProvider).userId;
      final isCallerNow = myUserId != null && callerId != null && myUserId == callerId;
      if (_isCaller != isCallerNow && mounted) {
        setState(() => _isCaller = isCallerNow);
      }

      if (!mounted) return;
      if (_callStatus != status) {
        setState(() => _callStatus = status);
      }

      if (status == 'ongoing') {
        if (!_rtcJoining && !_joined) {
          await _initRtc();
        }
        return;
      }

      if (status == 'pending' && _isLoading) {
        setState(() => _isLoading = false);
      }
      if (status == 'pending' && isCallerNow) {
        final left = _calcPendingLeftSeconds(createdAtRaw);
        if (mounted && left != _pendingLeftSeconds) {
          setState(() => _pendingLeftSeconds = left);
        }
      }

      if (status == 'ended') {
        await _handleEndedByRemote(endReason);
      }
    } catch (_) {
      // 状态轮询失败不立刻中断，保持页面等待下次轮询
    }
  }

  int _calcPendingLeftSeconds(String? createdAtRaw) {
    if (createdAtRaw == null || createdAtRaw.isEmpty) return _pendingLeftSeconds;
    final createdAt = DateTime.tryParse(createdAtRaw)?.toLocal();
    if (createdAt == null) return _pendingLeftSeconds;
    final elapsed = DateTime.now().difference(createdAt).inSeconds;
    final left = 30 - elapsed;
    return left > 0 ? left : 0;
  }

  Future<void> _initRtc() async {
    if (_rtcJoining || _joined || _hasEnded) return;
    _rtcJoining = true;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
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
        throw Exception('RTC 参数不完整');
      }

      final engine = createAgoraRtcEngine();
      _engine = engine;
      _channelName = channel;

      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            if (!mounted) return;
            setState(() {
              _joined = true;
              _localUid = connection.localUid;
            });
            _startDurationTimer();
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            if (!mounted) return;
            setState(() => _remoteUid = remoteUid);
          },
          onUserOffline: (
            RtcConnection connection,
            int remoteUid,
            UserOfflineReasonType reason,
          ) {
            if (!mounted) return;
            if (_remoteUid == remoteUid) {
              setState(() => _remoteUid = null);
            }
          },
          onError: (ErrorCodeType err, String msg) {
            if (!mounted) return;
            setState(() => _errorMessage = 'RTC 错误: $msg');
          },
        ),
      );

      await engine.initialize(
        RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      await engine.enableVideo();
      await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await engine.startPreview();

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

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '视频通话初始化失败，请稍后重试';
      });
    } finally {
      _rtcJoining = false;
    }
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _callStartTime = DateTime.now();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_callStartTime != null && mounted) {
        setState(() {
          _callDuration = DateTime.now().difference(_callStartTime!);
        });
      }
    });
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
        _endingInProgress = false;
        return;
      }

      final isPending = _callStatus == 'pending';
      await _leaveAndExit(cancelPending: isPending);
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tip)));
    }

    await _leaveAndExit(notifyEndApi: false);
  }

  Future<void> _leaveAndExit({
    bool cancelPending = false,
    bool notifyEndApi = true,
  }) async {
    if (_hasEnded) return;
    _hasEnded = true;

    _statusTimer?.cancel();
    _durationTimer?.cancel();

    try {
      if (cancelPending) {
        await DioClient.instance.apiPost(
          ApiEndpoints.callCancel,
          data: {'call_id': widget.callId},
        );
      } else if (notifyEndApi) {
        await DioClient.instance.apiPost(
          ApiEndpoints.callEnd,
          data: {'call_id': widget.callId},
        );
      }
    } catch (_) {}

    await _releaseRtcEngine();

    if (!mounted) return;
    context.go(AppRoutes.index);
  }

  Future<void> _releaseRtcEngine() async {
    final engine = _engine;
    _engine = null;
    if (engine == null) return;
    try {
      await engine.leaveChannel();
    } catch (_) {}
    try {
      await engine.release();
    } catch (_) {}
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

  void _showGiftPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GiftPanel(
        anchorId: widget.anchorId,
        onClose: () => Navigator.pop(context),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _durationTimer?.cancel();
    if (!_hasEnded) {
      unawaited(_releaseRtcEngine());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anchorState = ref.watch(anchorListProvider);
    AnchorInfo? found;
    for (final a in anchorState.anchors) {
      if (a.userId.toString() == widget.anchorId) {
        found = a;
        break;
      }
    }
    final anchor = found;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2D1F2F),
              Color(0xFF1A1A1A),
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildRemoteView(),
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
                    color: _isCameraOn ? const Color(0xFF2A2A2A) : Colors.black,
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
                    colors: [
                      Colors.black54,
                      Colors.transparent,
                    ],
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
                            anchor?.username ?? '主播',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _formatDuration(_callDuration),
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (anchor?.callPrice != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '￥${anchor!.callPrice!.toStringAsFixed(0)}/min',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
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
                    colors: [
                      Colors.black54,
                      Colors.transparent,
                    ],
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
                      onTap: _showGiftPanel,
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
                        child: const Icon(Icons.call_end, color: Colors.white, size: 30),
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
    if (!_isCameraOn || engine == null || !_joined) {
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
    String? subText;
    if (_callStatus == 'pending') {
      statusText = '等待对方接听...';
      if (_isCaller) {
        subText = '${_pendingLeftSeconds}s 后自动超时';
      }
    } else if (_joined) {
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
          if (subText != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                subText,
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
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
