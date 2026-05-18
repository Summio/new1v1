import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('im page shows peer availability status in app bar', () {
    final text = File('lib/modules/im/im_page.dart').readAsStringSync();

    expect(text, contains("../home/main_shell.dart"));
    expect(
      text,
      contains('StreamSubscription<PresenceEvent>? _presenceSubscription'),
    );
    expect(text, contains("String _peerAvailabilityStatus = 'offline'"));
    expect(text, contains("String _peerAvailabilityLabel = '离线'"));
    expect(text, contains('MainShell.presenceStream.listen('));
    expect(text, contains('_handlePresenceEvent,'));
    expect(text, contains('_presenceSubscription?.cancel()'));

    expect(text, contains("_normalizeAvailabilityStatus("));
    expect(text, contains("payload['availability_status']"));
    expect(text, contains("payload['availability_label']"));
    expect(text, contains("payload['is_online']"));
    expect(text, contains('_handlePresenceEvent(PresenceEvent event)'));
    expect(text, contains('event.availabilityStatus'));
    expect(text, contains('event.availabilityLabel'));

    expect(text, contains('_buildAppBarTitle()'));
    expect(text, contains('●'));
    expect(text, contains('AppTheme.onlineGreen'));
    expect(text, contains('Color(0xFFFF3B30)'));
    expect(text, contains('Color(0xFFAF52DE)'));
    expect(text, contains('AppTheme.offlineGray'));
  });

  test('customer service conversation keeps app bar title status-free', () {
    final text = File('lib/modules/im/im_page.dart').readAsStringSync();

    expect(text, contains("if (_isCustomerServiceConversation) {"));
    expect(text, contains('return const Text('));
    expect(text, contains("'在线客服'"));
  });
}
