import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('secondary page app bar titles are explicitly centered', () {
    final centeredTitles = <_CenteredTitleSpec>[
      _CenteredTitleSpec(
        'lib/modules/home/call_page.dart',
        "title: const Text('通话记录')",
      ),
      _CenteredTitleSpec(
        'lib/modules/home/complaint_page.dart',
        "title: const Text('投诉用户')",
      ),
      _CenteredTitleSpec(
        'lib/modules/home/feedback_page.dart',
        "title: const Text('意见反馈')",
      ),
      _CenteredTitleSpec(
        'lib/modules/home/system_notifications_page.dart',
        "title: const Text('系统通知')",
      ),
      _CenteredTitleSpec(
        'lib/modules/home/system_notification_detail_page.dart',
        "title: const Text('系统通知')",
      ),
      _CenteredTitleSpec(
        'lib/modules/home/my_following_page.dart',
        'title: Text(title)',
      ),
      _CenteredTitleSpec(
        'lib/modules/home/publish_moment_page.dart',
        "title: const Text('发布动态')",
      ),
      _CenteredTitleSpec(
        'lib/modules/home/certification_center_page.dart',
        "title: const Text('认证中心')",
      ),
      _CenteredTitleSpec(
        'lib/modules/home/certification_center_page.dart',
        "title: const Text('真人认证')",
      ),
      _CenteredTitleSpec(
        'lib/modules/home/certification_center_page.dart',
        "title: const Text('通话价格')",
      ),
      _CenteredTitleSpec(
        'lib/modules/home/certification_center_page.dart',
        "title: const Text('常用语')",
      ),
      _CenteredTitleSpec(
        'lib/modules/home/certification_center_page.dart',
        "title: const Text('前置摄像头自拍')",
      ),
      _CenteredTitleSpec(
        'lib/modules/profile/recharge_page.dart',
        "title: Text('\${tokenNames.coinName}充值')",
      ),
      _CenteredTitleSpec(
        'lib/modules/profile/withdraw_page.dart',
        "title: Text('\$diamondName提现')",
      ),
      _CenteredTitleSpec(
        'lib/modules/profile/withdraw_account_page.dart',
        "title: const Text('提现账户')",
      ),
      _CenteredTitleSpec(
        'lib/modules/profile/coin_transactions_page.dart',
        "title: Text('\${tokenNames.coinName}明细')",
      ),
      _CenteredTitleSpec(
        'lib/modules/profile/diamond_transactions_page.dart',
        "title: Text('\${tokenNames.diamondName}明细')",
      ),
      _CenteredTitleSpec(
        'lib/modules/profile/edit_profile_page.dart',
        "title: const Text('编辑资料')",
      ),
      _CenteredTitleSpec(
        'lib/modules/profile/do_not_disturb_page.dart',
        "title: const Text('勿扰模式')",
      ),
      _CenteredTitleSpec(
        'lib/modules/settings/settings_page.dart',
        "title: const Text('设置')",
      ),
      _CenteredTitleSpec(
        'lib/modules/settings/agreement_page.dart',
        "title: const Text('用户协议')",
      ),
      _CenteredTitleSpec(
        'lib/modules/settings/privacy_page.dart',
        "title: const Text('隐私政策')",
      ),
      _CenteredTitleSpec(
        'lib/modules/settings/change_password_page.dart',
        "title: const Text('修改密码')",
      ),
      _CenteredTitleSpec(
        'lib/modules/settings/teen_mode_setup_page.dart',
        "title: const Text('设置青少年模式')",
      ),
      _CenteredTitleSpec(
        'lib/modules/settings/teen_mode_verify_page.dart',
        "title: const Text('青少年模式')",
      ),
    ];

    for (final spec in centeredTitles) {
      final source = File(spec.path).readAsStringSync();
      final titleIndex = source.indexOf(spec.titleSnippet);
      expect(
        titleIndex,
        isNot(-1),
        reason: 'Missing title snippet `${spec.titleSnippet}` in ${spec.path}',
      );

      final windowStart = titleIndex - 180 < 0 ? 0 : titleIndex - 180;
      final windowEnd = titleIndex + 260 > source.length
          ? source.length
          : titleIndex + 260;
      final appBarWindow = source.substring(windowStart, windowEnd);
      expect(
        appBarWindow,
        contains('centerTitle: true'),
        reason:
            'AppBar title `${spec.titleSnippet}` in ${spec.path} must be centered',
      );
    }
  });
}

class _CenteredTitleSpec {
  const _CenteredTitleSpec(this.path, this.titleSnippet);

  final String path;
  final String titleSnippet;
}
