import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/providers/auth_provider.dart';

void main() {
  test('AppInitState parses customer service bootstrap config', () {
    final state = AppInitState.fromBootstrapMap({
      'token_names': {'coin_name': '金币', 'diamond_name': '钻石'},
      'im': {'configured': true, 'sdk_app_id': 12345},
      'customer_service': {
        'enabled': true,
        'user_id': 9001,
        'nickname': '在线客服',
        'avatar': 'https://example.com/avatar.png',
      },
      'im_text_billing': {
        'enabled': false,
        'price': 0,
        'certified_user_share_bps': 5000,
      },
      'certified_call_price_tiers': [0, 100, 200],
    });

    expect(state.coinName, '金币');
    expect(state.diamondName, '钻石');
    expect(state.imConfigured, isTrue);
    expect(state.imSdkAppId, 12345);
    expect(state.customerServiceEnabled, isTrue);
    expect(state.customerServiceUserId, '9001');
    expect(state.customerServiceNickname, '在线客服');
    expect(state.customerServiceAvatar, 'https://example.com/avatar.png');
  });
}
