import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/routes/app_router.dart';
import 'package:huanxi/app/providers/certified_user_provider.dart';
import 'package:huanxi/core/network/response_parsers.dart';
import 'package:huanxi/core/utils/conversation_refresh_throttler.dart';

void main() {
  group('AppRoutes', () {
    test('tryGetCertifiedUserInfo returns null for invalid extra', () {
      expect(AppRoutes.tryGetCertifiedUserInfo(null), isNull);
      expect(AppRoutes.tryGetCertifiedUserInfo({'id': 1}), isNull);
    });

    test('tryGetCertifiedUserInfo returns certified user for valid extra', () {
      const certifiedUser = CertifiedUserInfo(id: 1, userId: 2);
      expect(AppRoutes.tryGetCertifiedUserInfo(certifiedUser), certifiedUser);
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

    test('parseIMTextChargePayload parses valid payload', () {
      final parsed = ResponseParsers.parseIMTextChargePayload({
        'data': {
          'charged': true,
          'price': 20,
          'certified_user_income_diamonds': 10,
          'coins': 980,
          'diamonds': 0,
          'receiver_user_id': 2,
          'request_id': 'req_123456',
        }
      });
      expect(parsed.charged, isTrue);
      expect(parsed.price, 20);
      expect(parsed.certifiedUserIncomeDiamonds, 10);
      expect(parsed.coins, 980);
      expect(parsed.receiverUserId, 2);
      expect(parsed.requestId, 'req_123456');
    });

    test('parseIMTextChargePayload throws format exception when required fields missing', () {
      expect(
        () => ResponseParsers.parseIMTextChargePayload({'data': {}}),
        throwsA(isA<FormatException>()),
      );
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

