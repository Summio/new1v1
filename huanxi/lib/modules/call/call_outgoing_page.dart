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

class CallOutgoingPage extends StatefulWidget {
  final int callId;
  final String peerUserId;
  final String peerName;
  final String? peerAvatar;
  final String? anchorId;
  final int callPrice;

  const CallOutgoingPage({
    super.key,
    required this.callId,
    required this.peerUserId,
    required this.peerName,
    this.peerAvatar,
    this.anchorId,
    required this.callPrice,
  });

  @override
  State<CallOutgoingPage> createState() => _CallOutgoingPageState();
}

class _CallOutgoingPageState extends State<CallOutgoingPage> {
  Timer? _pollTimer;
  bool _pageClosing = false;
  bool _requestInFlight = false;
  bool _actionInFlight = false;
  int _leftSeconds = 30;

  @override
  void initState() {
    super.initState();
    _leftSeconds = 30;
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

      if (payload.callId != null && payload.callId != widget.callId) {
        return;
      }

      if (_leftSeconds != payload.leftSeconds && payload.leftSeconds >= 0) {
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
              'anchorId': widget.anchorId,
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

  Future<void> _cancelCall() async {
    if (_actionInFlight || _pageClosing) return;
    _actionInFlight = true;
    try {
      await DioClient.instance.apiPost(
        ApiEndpoints.callCancel,
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
        const SnackBar(content: Text('取消失败，请稍后重试')),
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
    final priceText = widget.callPrice > 0 ? '${widget.callPrice}/分' : '--';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _cancelCall();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF111827),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 48),
              CircleAvatar(
                radius: 52,
                backgroundColor: Colors.white12,
                backgroundImage:
                    (widget.peerAvatar != null && widget.peerAvatar!.isNotEmpty)
                    ? NetworkImage(widget.peerAvatar!)
                    : null,
                child:
                    (widget.peerAvatar == null || widget.peerAvatar!.isEmpty)
                    ? const Icon(Icons.person, color: Colors.white70, size: 48)
                    : null,
              ),
              const SizedBox(height: 20),
              Text(
                widget.peerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '视频呼叫中...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$_leftSeconds 秒后自动结束  ·  $priceText',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _cancelCall,
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: const BoxDecoration(
                    color: AppTheme.errorColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.call_end, color: Colors.white, size: 34),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '取消',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 56),
            ],
          ),
        ),
      ),
    );
  }
}
