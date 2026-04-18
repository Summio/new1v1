import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/core/im/call_trace_message.dart';
import 'package:huanxi/services/im_service.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';

V2TimMessage _buildCallTraceMessage(Map<String, dynamic> payload) {
  return V2TimMessage(
    elemType: MessageElemType.V2TIM_ELEM_TYPE_CUSTOM,
    customElem: V2TimCustomElem(
      data: jsonEncode(payload),
      desc: CallTraceMessage.protocol,
      extension: 'call_trace',
    ),
  );
}

void main() {
  test('CallTraceMessage.fromTimMessage parses valid payload', () {
    final msg = _buildCallTraceMessage({
      'protocol': 'call_trace.v1',
      'event_id': 'call:trace:101:dialing',
      'call_id': 101,
      'phase': 'dialing',
      'actor_user_id': 1001,
      'peer_user_id': 2002,
      'ts': 1720000000,
      'duration_seconds': 0,
      'total_fee_coins': 0,
      'reason': null,
    });

    final trace = CallTraceMessage.fromTimMessage(msg);
    expect(trace, isNotNull);
    expect(trace!.callId, 101);
    expect(trace.phase, 'dialing');
    expect(trace.toDisplayText(currentUserId: 1001), '你发起了视频通话');
    expect(trace.toDisplayText(currentUserId: 2002), '对方发起了视频通话');
  });

  test('CallTraceMessage.fromTimMessage returns null for invalid protocol', () {
    final msg = _buildCallTraceMessage({
      'protocol': 'unknown.v1',
      'event_id': 'call:trace:101:dialing',
      'call_id': 101,
      'phase': 'dialing',
      'actor_user_id': 1001,
      'peer_user_id': 2002,
      'ts': 1720000000,
      'duration_seconds': 0,
      'total_fee_coins': 0,
      'reason': null,
    });

    expect(CallTraceMessage.fromTimMessage(msg), isNull);
  });

  test('IMService.buildConversationPreview maps call trace message', () {
    final service = IMService();
    final msg = _buildCallTraceMessage({
      'protocol': 'call_trace.v1',
      'event_id': 'call:trace:101:rejected',
      'call_id': 101,
      'phase': 'rejected',
      'actor_user_id': 2002,
      'peer_user_id': 1001,
      'ts': 1720000000,
      'duration_seconds': 0,
      'total_fee_coins': 0,
      'reason': 'rejected',
    });

    final preview = service.buildConversationPreview(
      message: msg,
      currentUserId: 1001,
    );
    expect(preview, '对方已拒绝视频通话');
  });
}
