import 'package:flutter_test/flutter_test.dart';

import 'package:huanxi/modules/call/controllers/call_rtc_controller.dart';

void main() {
  group('resolveFrontCameraFromNativeState', () {
    test('优先使用 facing=front/back', () {
      expect(
        resolveFrontCameraFromNativeState(facing: 'front', cameraId: 0),
        isTrue,
      );
      expect(
        resolveFrontCameraFromNativeState(facing: 'back', cameraId: 1),
        isFalse,
      );
    });

    test('facing 缺失时回退 cameraId', () {
      expect(resolveFrontCameraFromNativeState(cameraId: 1), isTrue);
      expect(resolveFrontCameraFromNativeState(cameraId: 0), isFalse);
    });

    test('未知状态返回 null', () {
      expect(resolveFrontCameraFromNativeState(), isNull);
      expect(resolveFrontCameraFromNativeState(facing: 'unknown'), isNull);
      expect(resolveFrontCameraFromNativeState(cameraId: 9), isNull);
    });
  });

  group('resolveFrameRotationFromNativeState', () {
    test('仅接受 0/90/180/270', () {
      expect(resolveFrameRotationFromNativeState(0), 0);
      expect(resolveFrameRotationFromNativeState(90), 90);
      expect(resolveFrameRotationFromNativeState(180), 180);
      expect(resolveFrameRotationFromNativeState(270), 270);
    });

    test('非法输入返回 null', () {
      expect(resolveFrameRotationFromNativeState(null), isNull);
      expect(resolveFrameRotationFromNativeState(45), isNull);
      expect(resolveFrameRotationFromNativeState('90'), isNull);
    });
  });
}
