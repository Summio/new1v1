import 'dart:convert';

import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';

class CallTraceMessage {
  static const String protocol = 'call_trace.v1';
  static const Set<String> validPhases = <String>{
    'dialing',
    'accepted',
    'rejected',
    'cancelled',
    'ended',
    'timeout',
    'balance_empty',
    'force_exit',
  };

  final String eventId;
  final int callId;
  final String phase;
  final int actorUserId;
  final int peerUserId;
  final int ts;
  final int durationSeconds;
  final double totalFeeCoins;
  final int incomeAnchorUserId;
  final double anchorIncomeDiamonds;
  final String? reason;

  const CallTraceMessage({
    required this.eventId,
    required this.callId,
    required this.phase,
    required this.actorUserId,
    required this.peerUserId,
    required this.ts,
    required this.durationSeconds,
    required this.totalFeeCoins,
    required this.incomeAnchorUserId,
    required this.anchorIncomeDiamonds,
    this.reason,
  });

  static CallTraceMessage? fromTimMessage(V2TimMessage? message) {
    final custom = message?.customElem;
    if (custom == null) return null;

    final raw = custom.data?.trim() ?? '';
    if (raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      return fromJsonMap(map);
    } catch (_) {
      return null;
    }
  }

  static CallTraceMessage? fromJsonMap(Map<String, dynamic> json) {
    final p = (json['protocol'] as String?)?.trim();
    if (p != protocol) return null;

    final phase = (json['phase'] as String?)?.trim() ?? '';
    if (!validPhases.contains(phase)) return null;

    final eventId = (json['event_id'] as String?)?.trim() ?? '';
    if (eventId.isEmpty) return null;

    final callId = _asInt(json['call_id']);
    final actorUserId = _asInt(json['actor_user_id']);
    final peerUserId = _asInt(json['peer_user_id']);
    final ts = _asInt(json['ts']);
    final durationSeconds = _asInt(json['duration_seconds']);
    final totalFeeCoins = _asDouble(json['total_fee_coins']);
    final incomeAnchorUserId = _asInt(json['income_anchor_user_id']);
    final anchorIncomeDiamonds = _asDouble(json['anchor_income_diamonds']);
    final reason = (json['reason'] as String?)?.trim();

    if (callId <= 0 || actorUserId <= 0 || peerUserId <= 0) {
      return null;
    }

    return CallTraceMessage(
      eventId: eventId,
      callId: callId,
      phase: phase,
      actorUserId: actorUserId,
      peerUserId: peerUserId,
      ts: ts,
      durationSeconds: durationSeconds,
      totalFeeCoins: totalFeeCoins,
      incomeAnchorUserId: incomeAnchorUserId,
      anchorIncomeDiamonds: anchorIncomeDiamonds,
      reason: reason?.isEmpty == true ? null : reason,
    );
  }

  String toDisplayText({required int currentUserId}) {
    final isActor = currentUserId == actorUserId;
    switch (phase) {
      case 'dialing':
        return isActor ? '你发起了视频通话' : '对方发起了视频通话';
      case 'accepted':
        return isActor ? '你已接听视频通话' : '对方已接听视频通话';
      case 'rejected':
        return isActor ? '你已拒绝视频通话' : '对方已拒绝视频通话';
      case 'cancelled':
        return isActor ? '你已取消视频通话' : '对方已取消视频通话';
      case 'ended':
        return isActor ? '你已结束视频通话' : '对方已结束视频通话';
      case 'timeout':
        return isActor ? '你发起的视频通话无人接听' : '你有一通视频来电未接听';
      case 'balance_empty':
        return isActor ? '你的余额不足，通话已结束' : '对方余额不足，通话已结束';
      case 'force_exit':
        return isActor ? '你已离开，通话已结束' : '对方已离开，通话已结束';
      default:
        return '视频通话状态更新';
    }
  }

  String detailText({
    required int currentUserId,
    required bool isCurrentUserAnchor,
    String coinName = '金币',
    String diamondName = '钻石',
  }) {
    final parts = <String>[];
    if (durationSeconds > 0) {
      parts.add('时长 ${_formatDuration(durationSeconds)}');
    }
    final shouldShowIncome = isCurrentUserAnchor &&
        incomeAnchorUserId == currentUserId &&
        anchorIncomeDiamonds > 0;
    final shouldShowExpense = totalFeeCoins > 0 && !isCurrentUserAnchor;
    if (shouldShowIncome) {
      parts.add('收入 ${anchorIncomeDiamonds.toStringAsFixed(2)} $diamondName');
    } else if (shouldShowExpense) {
      parts.add('消费 ${totalFeeCoins.toStringAsFixed(2)} $coinName');
    }
    return parts.join(' · ');
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static String _formatDuration(int seconds) {
    final s = seconds.clamp(0, 24 * 3600);
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }
}
