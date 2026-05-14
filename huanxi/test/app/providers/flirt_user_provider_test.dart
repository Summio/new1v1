import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/providers/flirt_user_provider.dart';

void main() {
  group('FlirtUserInfo', () {
    test('parses balance and availability fields', () {
      final user = FlirtUserInfo.fromJson({
        'id': 23,
        'user_id': 23,
        'nickname': '小喜',
        'avatar': '/uploads/avatar.png',
        'gender': 'female',
        'coins': 1280.5,
        'is_certified_user': false,
        'is_online': true,
        'is_busy': false,
        'video_dnd_enabled': false,
        'availability_status': 'online',
        'availability_label': '在线',
      });

      expect(user.userId, 23);
      expect(user.username, '小喜');
      expect(user.coins, 1280.5);
      expect(user.isCertifiedUser, isFalse);
      expect(user.availabilityStatus, 'online');
      expect(user.availabilityLabel, '在线');
    });

    test('falls back to offline availability when status fields are missing', () {
      final user = FlirtUserInfo.fromJson({
        'id': 24,
        'user_id': 24,
        'nickname': '阿南',
        'coins': 86,
      });

      expect(user.coins, 86);
      expect(user.availabilityStatus, 'offline');
      expect(user.availabilityLabel, '离线');
    });
  });
}
