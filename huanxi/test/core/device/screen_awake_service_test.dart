import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/core/device/screen_awake_service.dart';

void main() {
  test(
    'reapplyIfNeeded keeps screen awake only when globally enabled',
    () async {
      var enableCount = 0;
      var disableCount = 0;

      final service = ScreenAwakeService(
        enable: () async {
          enableCount += 1;
        },
        disable: () async {
          disableCount += 1;
        },
      );

      await service.reapplyIfNeeded();
      expect(enableCount, 0);

      await service.enableGlobal();
      expect(service.isGlobalEnabled, isTrue);
      expect(enableCount, 1);

      await service.reapplyIfNeeded();
      expect(enableCount, 2);

      await service.disableGlobal();
      expect(service.isGlobalEnabled, isFalse);
      expect(disableCount, 1);

      await service.reapplyIfNeeded();
      expect(enableCount, 2);
    },
  );

  test('wakelock errors do not escape service calls', () async {
    var enableCount = 0;

    final service = ScreenAwakeService(
      enable: () async {
        enableCount += 1;
        throw StateError('wakelock unavailable');
      },
      disable: () async {},
      logError: (_, _, _) {},
    );

    await expectLater(service.enableGlobal(), completes);
    expect(service.isGlobalEnabled, isTrue);
    expect(enableCount, 1);

    await expectLater(service.reapplyIfNeeded(), completes);
    expect(enableCount, 2);
  });
}
