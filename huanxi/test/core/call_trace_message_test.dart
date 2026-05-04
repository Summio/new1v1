import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/core/im/call_trace_message.dart';

void main() {
  test('CallTraceMessage.fromJsonMap parses valid payload', () {
    final trace = CallTraceMessage.fromJsonMap({
      'protocol': 'call_trace.v1',
      'event_id': 'call:trace:101:dialing',
      'call_id': 101,
      'phase': 'dialing',
      'actor_user_id': 1001,
      'peer_user_id': 2002,
      'ts': 1720000000,
      'duration_seconds': 0,
      'total_fee_coins': 0,
      'income_anchor_user_id': 2002,
      'anchor_income_diamonds': 50,
      'reason': null,
    });

    expect(trace, isNotNull);
    expect(trace!.callId, 101);
    expect(trace.phase, 'dialing');
    expect(trace.toDisplayText(currentUserId: 1001), '你发起了视频通话');
    expect(trace.toDisplayText(currentUserId: 2002), '对方发起了视频通话');
  });

  test('CallTraceMessage.fromJsonMap returns null for invalid protocol', () {
    final trace = CallTraceMessage.fromJsonMap({
      'protocol': 'unknown.v1',
      'event_id': 'call:trace:101:dialing',
      'call_id': 101,
      'phase': 'dialing',
      'actor_user_id': 1001,
      'peer_user_id': 2002,
      'ts': 1720000000,
      'duration_seconds': 0,
      'total_fee_coins': 0,
      'income_anchor_user_id': 2002,
      'anchor_income_diamonds': 50,
      'reason': null,
    });

    expect(trace, isNull);
  });

  test('CallTraceMessage maps rejected preview text', () {
    final trace = CallTraceMessage.fromJsonMap({
      'protocol': 'call_trace.v1',
      'event_id': 'call:trace:101:rejected',
      'call_id': 101,
      'phase': 'rejected',
      'actor_user_id': 2002,
      'peer_user_id': 1001,
      'ts': 1720000000,
      'duration_seconds': 0,
      'total_fee_coins': 0,
      'income_anchor_user_id': 2002,
      'anchor_income_diamonds': 50,
      'reason': 'rejected',
    });

    expect(trace, isNotNull);
    expect(trace!.toDisplayText(currentUserId: 1001), '对方已拒绝视频通话');
  });

  test('detailText shows income for anchor view', () {
    final trace = CallTraceMessage.fromJsonMap({
      'protocol': 'call_trace.v1',
      'event_id': 'call:trace:101:ended',
      'call_id': 101,
      'phase': 'ended',
      'actor_user_id': 1001,
      'peer_user_id': 2002,
      'ts': 1720000000,
      'duration_seconds': 90,
      'total_fee_coins': 120,
      'income_anchor_user_id': 2002,
      'anchor_income_diamonds': 60,
      'reason': 'ended',
    });

    final text = trace!.detailText(
      currentUserId: 2002,
      isCurrentUserAnchor: true,
      coinName: '金币',
      diamondName: '钻石',
    );
    expect(text, '时长 01:30 · 收入 60 钻石');
  });

  test('detailText shows expense for user view', () {
    final trace = CallTraceMessage.fromJsonMap({
      'protocol': 'call_trace.v1',
      'event_id': 'call:trace:101:ended',
      'call_id': 101,
      'phase': 'ended',
      'actor_user_id': 1001,
      'peer_user_id': 2002,
      'ts': 1720000000,
      'duration_seconds': 90,
      'total_fee_coins': 120,
      'income_anchor_user_id': 2002,
      'anchor_income_diamonds': 60,
      'reason': 'ended',
    });

    final text = trace!.detailText(
      currentUserId: 1001,
      isCurrentUserAnchor: false,
      coinName: '金币',
      diamondName: '钻石',
    );
    expect(text, '时长 01:30 · 消费 120 金币');
  });

  test('detailText does not fallback to income when anchor income is absent', () {
    final trace = CallTraceMessage.fromJsonMap({
      'protocol': 'call_trace.v1',
      'event_id': 'call:trace:101:ended',
      'call_id': 101,
      'phase': 'ended',
      'actor_user_id': 1001,
      'peer_user_id': 2002,
      'ts': 1720000000,
      'duration_seconds': 90,
      'total_fee_coins': 120,
      'income_anchor_user_id': 0,
      'anchor_income_diamonds': 0,
      'reason': 'ended',
    });

    final text = trace!.detailText(
      currentUserId: 2002,
      isCurrentUserAnchor: true,
      coinName: '金币',
      diamondName: '钻石',
    );
    expect(text, '时长 01:30');
  });

  test('CallTraceMessage accepts force exit phase', () {
    final trace = CallTraceMessage.fromJsonMap({
      'protocol': 'call_trace.v1',
      'event_id': 'call:trace:101:force_exit',
      'call_id': 101,
      'phase': 'force_exit',
      'actor_user_id': 1001,
      'peer_user_id': 2002,
      'ts': 1720000000,
      'duration_seconds': 90,
      'total_fee_coins': 120,
      'income_anchor_user_id': 2002,
      'anchor_income_diamonds': 60,
      'reason': 'force_exit',
    });

    expect(trace, isNotNull);
    expect(trace!.toDisplayText(currentUserId: 1001), '你已离开，通话已结束');
  });
}
