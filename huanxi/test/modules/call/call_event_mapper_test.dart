import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/modules/call/call_event_mapper.dart';

void main() {
  group('CallEventMapper', () {
    test('maps call_balance_empty to balanceEmpty', () {
      final mapped = CallEventMapper.map(
        event: 'call_balance_empty',
        data: const {},
      );
      expect(mapped.endReason, CallEndReason.balanceEmpty);
      expect(mapped.shouldExit, isTrue);
    });

    test('maps call_balance_low to warning without exiting', () {
      final mapped = CallEventMapper.map(
        event: 'call_balance_low',
        data: const {},
      );
      expect(mapped.shouldShowBalanceLow, isTrue);
      expect(mapped.shouldExit, isFalse);
      expect(mapped.endReason, isNull);
    });

    test('maps force_exit end reason from call_ended', () {
      final mapped = CallEventMapper.map(
        event: 'call_ended',
        data: const {'end_reason': 'force_exit'},
      );
      expect(mapped.endReason, CallEndReason.forceExit);
      expect(mapped.shouldExit, isTrue);
    });

    test('maps unknown event to no-op', () {
      final mapped = CallEventMapper.map(event: 'unknown', data: const {});
      expect(mapped.shouldExit, isFalse);
      expect(mapped.endReason, isNull);
    });
  });
}
