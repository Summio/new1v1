import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/app_toast.dart';
import 'call_end_reason.dart';
import 'call_session_payload.dart';

class IncomingCallPage extends StatefulWidget {
  final int callId;
  final String peerUserId;
  final String peerName;
  final String? peerAvatar;

  const IncomingCallPage({
    super.key,
    required this.callId,
    required this.peerUserId,
    required this.peerName,
    this.peerAvatar,
  });

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  Timer? _pollTimer;
  bool _requestInFlight = false;
  bool _actionInFlight = false;
  bool _pageClosing = false;
  int _leftSeconds = 30;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _refreshSession();
    });
    _refreshSession();
  }

  Future<void> _refreshSession() async {
    if (_pageClosing || _requestInFlight) return;
    _requestInFlight = true;
    try {
      final res = await DioClient.instance.apiGet(ApiEndpoints.callSessionCurrent);
      final payload = CallSessionPayload.fromJson(
        res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : null,
      );
      if (!mounted || _pageClosing) return;
      if (payload.callId != null && payload.callId != widget.callId) return;

      if (payload.leftSeconds >= 0 && payload.leftSeconds != _leftSeconds) {
        setState(() => _leftSeconds = payload.leftSeconds);
      }

      if (payload.isOngoing) {
        _pageClosing = true;
        _pollTimer?.cancel();
        context.pushReplacement(
          Uri(
            path: AppRoutes.callRoom,
            queryParameters: {
              'callId': widget.callId.toString(),
              'peerUserId': widget.peerUserId,
              'peerName': widget.peerName,
            },
          ).toString(),
        );
        return;
      }

      if (payload.isEnded || payload.isIdle) {
        _pageClosing = true;
        _pollTimer?.cancel();
        AppToast.showSnackBar(
          context,
          SnackBar(content: Text(callEndReasonText(payload.endReason))),
        );
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRoutes.index);
        }
      }
    } catch (_) {
      // keep polling
    } finally {
      _requestInFlight = false;
    }
  }

  Future<void> _acceptCall() async {
    if (_actionInFlight || _pageClosing) return;
    _actionInFlight = true;
    try {
      await DioClient.instance.apiPost(
        ApiEndpoints.callAccept,
        data: {'call_id': widget.callId},
      );
      if (!mounted) return;
      _pageClosing = true;
      _pollTimer?.cancel();
      context.pushReplacement(
        Uri(
          path: AppRoutes.callRoom,
          queryParameters: {
            'callId': widget.callId.toString(),
            'peerUserId': widget.peerUserId,
            'peerName': widget.peerName,
          },
        ).toString(),
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('接听失败，请重试')),
      );
    } finally {
      _actionInFlight = false;
    }
  }

  Future<void> _rejectCall() async {
    if (_actionInFlight || _pageClosing) return;
    _actionInFlight = true;
    try {
      await DioClient.instance.apiPost(
        ApiEndpoints.callReject,
        data: {'call_id': widget.callId},
      );
      if (!mounted) return;
      _pageClosing = true;
      _pollTimer?.cancel();
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.index);
      }
    } catch (_) {
      if (!mounted) return;
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('拒绝失败，请重试')),
      );
    } finally {
      _actionInFlight = false;
    }
  }

  @override
  void dispose() {
    _pageClosing = true;
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 48),
              Text(
                '视频来电',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              CircleAvatar(
                radius: 56,
                backgroundColor: Colors.white12,
                backgroundImage:
                    (widget.peerAvatar != null && widget.peerAvatar!.isNotEmpty)
                    ? NetworkImage(widget.peerAvatar!)
                    : null,
                child:
                    (widget.peerAvatar == null || widget.peerAvatar!.isEmpty)
                    ? const Icon(Icons.person, color: Colors.white70, size: 50)
                    : null,
              ),
              const SizedBox(height: 18),
              Text(
                widget.peerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$_leftSeconds 秒后自动挂断',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ActionButton(
                      color: AppTheme.errorColor,
                      icon: Icons.call_end,
                      label: '拒绝',
                      onTap: _rejectCall,
                    ),
                    _ActionButton(
                      color: const Color(0xFF22C55E),
                      icon: Icons.call,
                      label: '接听',
                      onTap: _acceptCall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 56),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
