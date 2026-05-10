import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/modules/call/controllers/call_session_controller.dart';

void main() {
  group('CallSessionNotifier', () {
    test('balance empty ending overrides an earlier ending reason', () {
      final notifier = CallSessionNotifier(callId: 77);

      expect(
        notifier.beginEnding(endReason: 'peer_left', notifyEndApi: true),
        isTrue,
      );
      expect(notifier.state.phase, CallPhase.ending);
      expect(notifier.state.endReason, 'peer_left');
      expect(notifier.state.notifyEndApi, isTrue);

      expect(
        notifier.beginEnding(
          endReason: 'balance_empty',
          notifyEndApi: false,
          endingForBalance: true,
        ),
        isTrue,
      );
      expect(notifier.state.phase, CallPhase.ending);
      expect(notifier.state.endReason, 'balance_empty');
      expect(notifier.state.isEndingForBalance, isTrue);
      expect(notifier.state.notifyEndApi, isFalse);

      notifier.dispose();
    });
  });
}
