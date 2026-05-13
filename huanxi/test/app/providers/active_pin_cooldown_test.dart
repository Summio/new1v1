import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/providers/certified_user_provider.dart';

void main() {
  test('formats active pin cooldown remaining seconds', () {
    expect(formatActivePinCooldownMessage(1), '置顶太频繁，请 1 秒后再试');
    expect(formatActivePinCooldownMessage(59), '置顶太频繁，请 59 秒后再试');
    expect(formatActivePinCooldownMessage(60), '置顶太频繁，请 1 分钟后再试');
    expect(formatActivePinCooldownMessage(61), '置顶太频繁，请 2 分钟后再试');
    expect(formatActivePinCooldownMessage(3600), '置顶太频繁，请 1 小时后再试');
    expect(formatActivePinCooldownMessage(3661), '置顶太频繁，请 1 小时 2 分钟后再试');
  });
}
