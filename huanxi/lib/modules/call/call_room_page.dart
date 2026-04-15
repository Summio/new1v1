import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes/app_router.dart';
import '../../app/providers/anchor_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../gift/gift_panel.dart';

/// 通话房间页面
/// 显示远端画面 + 本地预览 + 控制栏
/// 5秒心跳定时器维持通话状态
class CallRoomPage extends ConsumerStatefulWidget {
  final String roomId;
  final String anchorId;

  const CallRoomPage({
    super.key,
    required this.roomId,
    required this.anchorId,
  });

  @override
  ConsumerState<CallRoomPage> createState() => _CallRoomPageState();
}

class _CallRoomPageState extends ConsumerState<CallRoomPage> {
  Timer? _heartbeatTimer;
  bool _isMicOn = true;
  bool _isSpeakerOn = true;
  bool _isCameraOn = true;
  bool _isFlipping = false;
  Duration _callDuration = Duration.zero;
  Timer? _durationTimer;
  DateTime? _callStartTime;

  @override
  void initState() {
    super.initState();
    _callStartTime = DateTime.now();
    _startHeartbeat();
    _startDurationTimer();
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(
      Duration(milliseconds: AppConstants.heartbeatIntervalMs),
      (_) => _sendHeartbeat(),
    );
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_callStartTime != null && mounted) {
        setState(() {
          _callDuration = DateTime.now().difference(_callStartTime!);
        });
      }
    });
  }

  Future<void> _sendHeartbeat() async {
    // TODO: 调用心跳 API
    // ref.read(callSessionProvider.notifier).sendHeartbeat(widget.roomId);
  }

  Future<void> _endCall() async {
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

    if (confirmed != true) return;
    if (!mounted) return;

    // TODO: 调用结束通话 API
    // await ref.read(callSessionProvider.notifier).endCall(widget.roomId);

    context.go(AppRoutes.index);
  }

  void _toggleMic() => setState(() => _isMicOn = !_isMicOn);
  void _toggleSpeaker() => setState(() => _isSpeakerOn = !_isSpeakerOn);
  void _toggleCamera() => setState(() => _isCameraOn = !_isCameraOn);

  void _flipCamera() {
    setState(() => _isFlipping = true);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _isFlipping = false);
    });
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
    _heartbeatTimer?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anchorState = ref.watch(anchorListProvider);
    // 查找对应主播
    AnchorInfo? found;
    for (final a in anchorState.anchors) {
      if (a.userId.toString() == widget.anchorId) {
        found = a;
        break;
      }
    }
    final anchor = found;

    return Scaffold(
      // 深色渐变背景
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
            // 远端画面（主播画面）
            anchor?.avatar != null && anchor!.avatar!.isNotEmpty
                ? Image.network(
                    anchor.avatar!,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, trace) => _buildPlaceholder(),
                  )
                : _buildPlaceholder(),

            // 本地预览（右上角小窗口）
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: GestureDetector(
                onTap: _flipCamera,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 90,
                  height: 120,
                  decoration: BoxDecoration(
                    color: _isCameraOn ? const Color(0xFF2A2A2A) : Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: _isCameraOn
                      ? const Icon(Icons.person, color: Colors.white30, size: 40)
                      : const Icon(Icons.videocam_off, color: Colors.white30, size: 32),
                ),
              ),
            ),

            // 顶部状态栏 - 毛玻璃
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
                decoration: BoxDecoration(
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
                          '¥${anchor!.callPrice!.toStringAsFixed(0)}/min',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 底部控制栏 - 毛玻璃
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
                decoration: BoxDecoration(
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
                      onTap: _toggleMic,
                    ),
                    _ControlButton(
                      icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                      label: '扬声器',
                      isActive: !_isSpeakerOn,
                      onTap: _toggleSpeaker,
                    ),
                    _ControlButton(
                      icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
                      label: '摄像头',
                      isActive: !_isCameraOn,
                      onTap: _toggleCamera,
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
                      onTap: _flipCamera,
                    ),
                    // 挂断按钮 - 珊瑚红
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
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
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
          const Text(
            '等待主播接听...',
            style: TextStyle(color: Colors.white54, fontSize: 16),
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
            duration: const Duration(milliseconds: 200),
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
