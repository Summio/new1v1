import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/anchor_provider.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/app_logger.dart';
import '../beauty/beauty_camera_view.dart';
import '../beauty/beauty_panel.dart';
import '../gift/gift_panel.dart';
import 'call_end_reason.dart';
import 'controllers/call_gift_controller.dart';
import 'controllers/call_rtc_controller.dart';
import 'controllers/call_session_controller.dart';
import 'controllers/call_ws_controller.dart';

/// 通话房间页面
/// 页面职责：渲染 + 交互分发 + side-effect 监听
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
  static const double _beautyPanelInitialFactor = 0.42;
  bool _endingConsuming = false;
  bool _disposed = false;
  bool _isRemoteInMainView = true;
  bool _isBeautyPanelVisible = false;
  double _beautyPanelHeightFactor = _beautyPanelInitialFactor;

  void _log(String message) {
    AppLogger.debug('[CALL_FLOW][callId=${widget.callId}] $message');
  }

  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]),
    );
    _log(
      'page init, peerUserId=${widget.peerUserId}, '
      'anchorId=${widget.anchorId}, peerName=${widget.peerName}',
    );

    // 使用 Future.microtask 延迟执行，避免 widget build 阶段修改 provider
    Future.microtask(() {
      if (!mounted) return;
      ref.read(callSessionProvider(widget.callId).notifier).markConnecting();
      ref.read(callWsControllerProvider(widget.callId).notifier).bind();

      unawaited(
        ref
            .read(callRtcControllerProvider(widget.callId).notifier)
            .initRtc(
              onCallConnected: () {
                if (!mounted) return;
                ref
                    .read(callSessionProvider(widget.callId).notifier)
                    .markOngoing();
              },
              onRemoteEnd: (endReason) {
                if (!mounted) return;
                ref
                    .read(callSessionProvider(widget.callId).notifier)
                    .beginEnding(endReason: endReason, notifyEndApi: false);
              },
              onLog: _log,
              faceBeautyKey: ref.read(faceBeautyKeyProvider),
            ),
      );
    });
  }

  Future<void> _consumeEnding(CallSessionState sessionState) async {
    if (_endingConsuming || sessionState.hasEnded) {
      return;
    }
    _endingConsuming = true;

    final endReason = (sessionState.endReason ?? 'normal').trim();
    _log(
      'session ending, reason=$endReason notifyEndApi=${sessionState.notifyEndApi}',
    );

    try {
      if (sessionState.isEndingForBalance || endReason == 'balance_empty') {
        if (mounted) {
          AppToast.showSnackBar(
            context,
            const SnackBar(content: Text('余额不足，通话即将结束')),
          );
        }
        await Future.delayed(const Duration(seconds: 3));
      } else if (endReason != 'normal') {
        if (mounted) {
          AppToast.showSnackBar(
            context,
            SnackBar(content: Text(callEndReasonText(endReason))),
          );
        }
      }

      final current = ref.read(callSessionProvider(widget.callId));
      if (!current.hasEnded) {
        await _leaveAndExit(
          notifyEndApi: current.notifyEndApi,
          endReason: endReason,
        );
      }
    } finally {
      _endingConsuming = false;
    }
  }

  Future<void> _endCall() async {
    final session = ref.read(callSessionProvider(widget.callId));
    if (session.endingInProgress || session.hasEnded) {
      return;
    }

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
      return;
    }

    _log('end call confirmed');
    ref
        .read(callSessionProvider(widget.callId).notifier)
        .beginEnding(endReason: 'normal', notifyEndApi: true);
  }

  Future<void> _leaveAndExit({
    required bool notifyEndApi,
    required String endReason,
  }) async {
    final sessionNotifier = ref.read(
      callSessionProvider(widget.callId).notifier,
    );
    final current = ref.read(callSessionProvider(widget.callId));
    if (current.hasEnded) {
      return;
    }

    _log('leave and exit start, notifyEndApi=$notifyEndApi reason=$endReason');

    try {
      if (notifyEndApi) {
        await DioClient.instance.apiPost(
          ApiEndpoints.callEnd,
          data: {'call_id': widget.callId},
        );
      }
    } catch (_) {}

    ref.read(callWsControllerProvider(widget.callId).notifier).unbind();
    await ref
        .read(callRtcControllerProvider(widget.callId).notifier)
        .leaveAndRelease(onLog: _log);
    sessionNotifier.markEnded(endReason: endReason);

    if (!mounted) {
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.index);
    }
  }

  int? _resolveGiftTargetAnchorId(AnchorInfo? anchor) {
    final fromRoute = int.tryParse((widget.anchorId ?? '').trim());
    if (fromRoute != null && fromRoute > 0) {
      return fromRoute;
    }
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

  void _toggleBeautyPanel() {
    setState(() {
      if (_isBeautyPanelVisible) {
        _isBeautyPanelVisible = false;
        return;
      }
      // 通话中调美颜时，优先让本地画面全屏，符合主流产品交互习惯。
      _isRemoteInMainView = false;
      _beautyPanelHeightFactor = _beautyPanelInitialFactor;
      _isBeautyPanelVisible = true;
    });
  }

  void _closeBeautyPanel() {
    if (!_isBeautyPanelVisible) return;
    setState(() {
      _isBeautyPanelVisible = false;
    });
  }

  Widget _buildInlineBeautyPanel(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final minHeight = computeCallBeautySheetMinHeight(screenHeight);
    final maxHeight = computeCallBeautySheetMaxHeight(screenHeight);
    final panelHeight = (_beautyPanelHeightFactor * screenHeight)
        .clamp(minHeight, maxHeight)
        .toDouble();

    void resizeByDeltaY(double deltaY) {
      final currentHeight = (_beautyPanelHeightFactor * screenHeight)
          .clamp(minHeight, maxHeight)
          .toDouble();
      final nextHeight = (currentHeight - deltaY).clamp(minHeight, maxHeight);
      setState(() {
        _beautyPanelHeightFactor = nextHeight / screenHeight;
      });
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: panelHeight,
        child: Stack(
          children: [
            const BeautyPanel(),
            Positioned(
              top: 0,
              left: 0,
              right: 44,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: (details) {
                  resizeByDeltaY(details.delta.dy);
                },
                child: const SizedBox(height: 36),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: _closeBeautyPanel,
                icon: const Icon(Icons.close, color: Colors.white70),
                tooltip: '关闭美颜面板',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  bool _shouldBestEffortTerminateOnDispose() {
    final session = ref.read(callSessionProvider(widget.callId));
    final rtcState = ref.read(callRtcControllerProvider(widget.callId));
    return !session.hasEnded && rtcState.isJoined;
  }

  Future<void> _bestEffortTerminateCall() async {
    final session = ref.read(callSessionProvider(widget.callId));
    if (session.hasEnded) {
      return;
    }
    _log('best effort terminate start');
    try {
      await DioClient.instance.apiPost(
        ApiEndpoints.callEnd,
        data: {'call_id': widget.callId},
      );
    } catch (_) {}
    _log('best effort terminate end');
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    Future.microtask(() {
      if (!_disposed) {
        ref.read(callWsControllerProvider(widget.callId).notifier).unbind();
        ref
            .read(callRtcControllerProvider(widget.callId).notifier)
            .leaveAndRelease(onLog: _log);
      }
    });
    if (_shouldBestEffortTerminateOnDispose()) {
      unawaited(_bestEffortTerminateCall());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<CallSessionState>(callSessionProvider(widget.callId), (
      previous,
      next,
    ) {
      if (next.phase == CallPhase.ending &&
          previous?.phase != CallPhase.ending) {
        unawaited(_consumeEnding(next));
      }
    });

    final rtcState = ref.watch(callRtcControllerProvider(widget.callId));
    final rtcController = ref.watch(
      callRtcControllerProvider(widget.callId).notifier,
    );
    final sessionState = ref.watch(callSessionProvider(widget.callId));
    final giftState = ref.watch(callGiftControllerProvider(widget.callId));

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
              if (rtcState.isCameraOn)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(opacity: 0.01, child: BeautyCameraView()),
                  ),
                ),
              _buildRemoteView(
                rtcState: rtcState,
                rtcController: rtcController,
              ),
              if (giftState.isShowing)
                _buildGiftAnimationOverlay(giftState: giftState),
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 16,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isRemoteInMainView = !_isRemoteInMainView;
                      _isBeautyPanelVisible = false;
                    });
                  },
                  child: AnimatedContainer(
                    duration: Duration.zero,
                    width: 90,
                    height: 160,
                    decoration: BoxDecoration(
                      color: rtcState.isCameraOn
                          ? const Color(0xFF2A2A2A)
                          : Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: _isRemoteInMainView
                        ? _buildLocalPreview(
                            rtcState: rtcState,
                            rtcController: rtcController,
                          )
                        : _buildRemoteVideo(
                            rtcState: rtcState,
                            rtcController: rtcController,
                            usePlaceholder: false,
                          ),
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
                              _formatDuration(sessionState.callDuration),
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
              if (!_isBeautyPanelVisible)
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
                          icon: rtcState.isMicOn ? Icons.mic : Icons.mic_off,
                          label: rtcState.isMicOn ? '麦克风' : '静音',
                          isActive: !rtcState.isMicOn,
                          onTap: () => unawaited(rtcController.toggleMic()),
                        ),
                        _ControlButton(
                          icon: rtcState.isSpeakerOn
                              ? Icons.volume_up
                              : Icons.volume_off,
                          label: '扬声器',
                          isActive: !rtcState.isSpeakerOn,
                          onTap: () => unawaited(rtcController.toggleSpeaker()),
                        ),
                        _ControlButton(
                          icon: rtcState.isCameraOn
                              ? Icons.videocam
                              : Icons.videocam_off,
                          label: '摄像头',
                          isActive: !rtcState.isCameraOn,
                          onTap: () => unawaited(rtcController.toggleCamera()),
                        ),
                        _ControlButton(
                          icon: Icons.card_giftcard,
                          label: '礼物',
                          onTap: () => _showGiftPanel(anchor),
                        ),
                        _ControlButton(
                          icon: Icons.auto_awesome,
                          label: '美颜',
                          isActive: _isBeautyPanelVisible,
                          onTap: _toggleBeautyPanel,
                        ),
                        _ControlButton(
                          icon: Icons.flip_camera_ios,
                          label: '翻转',
                          isSpinning: rtcState.isFlipping,
                          onTap: () => unawaited(rtcController.flipCamera()),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!_isBeautyPanelVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.of(context).padding.bottom + 116,
                  child: Center(
                    child: GestureDetector(
                      onTap: _endCall,
                      child: Container(
                        width: 62,
                        height: 62,
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
                  ),
                ),
              if (_isBeautyPanelVisible)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _closeBeautyPanel,
                    child: const SizedBox.expand(),
                  ),
                ),
              if (_isBeautyPanelVisible) _buildInlineBeautyPanel(context),
              if (rtcState.isLoading)
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

  Widget _buildRemoteView({
    required CallRtcState rtcState,
    required CallRtcController rtcController,
  }) {
    if (!_isRemoteInMainView) {
      return Positioned.fill(
        child: _buildLocalPreview(
          rtcState: rtcState,
          rtcController: rtcController,
        ),
      );
    }

    return Positioned.fill(
      child: _buildRemoteVideo(
        rtcState: rtcState,
        rtcController: rtcController,
        usePlaceholder: true,
      ),
    );
  }

  Widget _buildRemoteVideo({
    required CallRtcState rtcState,
    required CallRtcController rtcController,
    required bool usePlaceholder,
  }) {
    final engine = rtcController.engine;
    if (rtcState.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            rtcState.errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }

    if (rtcState.remoteUid != null &&
        engine != null &&
        rtcState.channelName != null) {
      final viewKey = usePlaceholder
          ? ValueKey('remote_full_${widget.callId}_${rtcState.remoteUid}')
          : ValueKey('remote_preview_${widget.callId}_${rtcState.remoteUid}');
      return AgoraVideoView(
        key: viewKey,
        controller: VideoViewController.remote(
          rtcEngine: engine,
          canvas: VideoCanvas(
            uid: rtcState.remoteUid,
            renderMode: RenderModeType.renderModeFit,
            mirrorMode: VideoMirrorModeType.videoMirrorModeDisabled,
          ),
          connection: RtcConnection(
            channelId: rtcState.channelName,
            localUid: rtcState.localUid,
          ),
          // 与本地 BeautyCameraView(PlatformView) 同屏时优先 Texture，避免 Android 叠层黑屏。
          useFlutterTexture: true,
        ),
      );
    }

    if (!usePlaceholder) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.person, color: Colors.white30, size: 28),
        ),
      );
    }

    return _buildPlaceholder(rtcState);
  }

  Widget _buildLocalPreview({
    required CallRtcState rtcState,
    required CallRtcController rtcController,
  }) {
    if (!rtcState.isCameraOn) {
      return const Icon(Icons.videocam_off, color: Colors.white30, size: 32);
    }

    if (rtcState.isFlipping) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: Colors.white70,
          ),
        ),
      );
    }

    final engine = rtcController.engine;
    if (engine == null) {
      return const Center(
        child: Icon(Icons.videocam, color: Colors.white70, size: 30),
      );
    }

    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: engine,
        canvas: VideoCanvas(
          uid: 0,
          sourceType: VideoSourceType.videoSourceCustom,
          renderMode: RenderModeType.renderModeHidden,
          mirrorMode: rtcState.isFrontCamera
              ? VideoMirrorModeType.videoMirrorModeDisabled
              : VideoMirrorModeType.videoMirrorModeDisabled,
        ),
        useFlutterTexture: true,
      ),
    );
  }

  Widget _buildPlaceholder(CallRtcState rtcState) {
    final statusText = rtcState.hasPeerLeft
        ? '对方已离开通话'
        : (rtcState.isJoined ? '等待对方加入...' : '正在连接视频通话...');

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
          if (rtcState.localUid != null && rtcState.channelName != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '频道: ${rtcState.channelName}  UID: ${rtcState.localUid}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGiftAnimationOverlay({required CallGiftState giftState}) {
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
                  giftState.giftIcon.isNotEmpty
                      ? Image.network(
                          giftState.giftIcon,
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
                        giftState.senderNickname,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '送出了 ${giftState.giftName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (giftState.giftPrice > 0)
                        Text(
                          '价值 ¥${giftState.giftPrice.toStringAsFixed(0)}',
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

double computeCallBeautySheetMaxHeight(double screenHeight) {
  final maxByRatio = screenHeight * 0.72;
  return maxByRatio.clamp(420.0, 680.0).toDouble();
}

double computeCallBeautySheetMinHeight(double screenHeight) {
  final minByRatio = screenHeight * 0.32;
  return minByRatio.clamp(260.0, 420.0).toDouble();
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
