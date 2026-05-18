import '../../core/utils/media_url.dart';

class CallSessionPayload {
  final int? callId;
  final String status;
  final String? role;
  final String? endReason;
  final int? peerUserId;
  final String peerNickname;
  final String? peerAvatar;
  final bool peerIsVip;
  final int callPrice;
  final int ringTimeoutSeconds;
  final int leftSeconds;
  final String? createdAt;
  final String? connectedAt;
  final int duration;
  final bool canAccept;
  final bool canReject;
  final bool canCancel;
  final bool canHangup;

  const CallSessionPayload({
    required this.callId,
    required this.status,
    required this.role,
    required this.endReason,
    required this.peerUserId,
    required this.peerNickname,
    required this.peerAvatar,
    this.peerIsVip = false,
    required this.callPrice,
    required this.ringTimeoutSeconds,
    required this.leftSeconds,
    required this.createdAt,
    required this.connectedAt,
    required this.duration,
    required this.canAccept,
    required this.canReject,
    required this.canCancel,
    required this.canHangup,
  });

  bool get isIdle => status == 'idle';
  bool get isPending => status == 'pending';
  bool get isOngoing => status == 'ongoing';
  bool get isEnded => status == 'ended';

  static int _toInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == '1' || normalized == 'true';
    }
    return false;
  }

  factory CallSessionPayload.fromJson(Map<String, dynamic>? json) {
    final payload = json ?? const <String, dynamic>{};
    final actions = payload['actions'] is Map<String, dynamic>
        ? payload['actions'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final peerNicknameRaw = (payload['peer_nickname'] as String?)?.trim();
    return CallSessionPayload(
      callId: _toInt(payload['call_id'], fallback: 0) > 0
          ? _toInt(payload['call_id'], fallback: 0)
          : null,
      status: (payload['status'] as String?)?.trim() ?? 'idle',
      role: (payload['role'] as String?)?.trim(),
      endReason: (payload['end_reason'] as String?)?.trim(),
      peerUserId: _toInt(payload['peer_user_id'], fallback: 0) > 0
          ? _toInt(payload['peer_user_id'], fallback: 0)
          : null,
      peerNickname: (peerNicknameRaw != null && peerNicknameRaw.isNotEmpty)
          ? peerNicknameRaw
          : '用户',
      peerAvatar: toAbsoluteMediaUrl(
        (payload['peer_avatar'] as String?)?.trim(),
      ),
      peerIsVip: _toBool(payload['peer_is_vip']),
      callPrice: _toInt(payload['call_price']),
      ringTimeoutSeconds: _toInt(payload['ring_timeout_seconds'], fallback: 30),
      leftSeconds: _toInt(payload['left_seconds']),
      createdAt: (payload['created_at'] as String?)?.trim(),
      connectedAt: (payload['connected_at'] as String?)?.trim(),
      duration: _toInt(payload['duration']),
      canAccept: _toBool(actions['can_accept']),
      canReject: _toBool(actions['can_reject']),
      canCancel: _toBool(actions['can_cancel']),
      canHangup: _toBool(actions['can_hangup']),
    );
  }
}
