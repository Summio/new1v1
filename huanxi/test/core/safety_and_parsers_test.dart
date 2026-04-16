import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/routes/app_router.dart';
import 'package:huanxi/app/providers/anchor_provider.dart';
import 'package:huanxi/core/network/response_parsers.dart';
import 'package:huanxi/core/utils/conversation_refresh_throttler.dart';

void main() {
  group('AppRoutes', () {
    test('tryGetAnchorInfo returns null for invalid extra', () {
      expect(AppRoutes.tryGetAnchorInfo(null), isNull);
      expect(AppRoutes.tryGetAnchorInfo({'id': 1}), isNull);
    });

    test('tryGetAnchorInfo returns anchor for valid extra', () {
      const anchor = AnchorInfo(id: 1, userId: 2);
      expect(AppRoutes.tryGetAnchorInfo(anchor), anchor);
    });
  });

  group('ResponseParsers', () {
    test('parseUserSigPayload throws format exception when required fields missing', () {
      expect(
        () => ResponseParsers.parseUserSigPayload({'data': {}}),
        throwsA(isA<FormatException>()),
      );
    });

    test('parseUserSigPayload parses valid payload', () {
      final parsed = ResponseParsers.parseUserSigPayload({
        'data': {'usersig': 'abc', 'sdk_app_id': 12345}
      });
      expect(parsed.userSig, 'abc');
      expect(parsed.sdkAppId, 12345);
    });
  });

  group('ConversationRefreshThrottler', () {
    test('canRefresh returns false within throttle window', () {
      final throttler = ConversationRefreshThrottler(interval: const Duration(seconds: 2));
      expect(throttler.canRefresh(now: DateTime(2026, 1, 1, 10)), isTrue);
      expect(throttler.canRefresh(now: DateTime(2026, 1, 1, 10, 0, 1)), isFalse);
      expect(throttler.canRefresh(now: DateTime(2026, 1, 1, 10, 0, 2)), isTrue);
    });
  });
}
