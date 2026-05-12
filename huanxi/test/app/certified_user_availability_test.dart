import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/providers/certified_user_provider.dart';

void main() {
  test(
    'CertifiedUserInfo parses availability fields and falls back from is_online',
    () {
      final busy = CertifiedUserInfo.fromJson({
        'id': 1,
        'user_id': 1,
        'is_online': true,
        'is_busy': true,
        'video_dnd_enabled': false,
        'availability_status': 'busy',
        'availability_label': '忙碌',
      });

      expect(busy.availabilityStatus, 'busy');
      expect(busy.availabilityLabel, '忙碌');
      expect(busy.isBusy, isTrue);
      expect(busy.videoDndEnabled, isFalse);

      final legacy = CertifiedUserInfo.fromJson({
        'id': 2,
        'user_id': 2,
        'is_online': false,
      });

      expect(legacy.availabilityStatus, 'offline');
      expect(legacy.availabilityLabel, '离线');
    },
  );
}
