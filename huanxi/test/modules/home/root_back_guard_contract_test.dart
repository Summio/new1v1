import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first-level tab routes disable system back inside shell navigator', () {
    final guard = File('lib/core/widgets/root_back_guard.dart');
    expect(guard.existsSync(), isTrue);

    final guardSource = guard.readAsStringSync();
    expect(guardSource, contains('class RootBackGuard'));
    expect(guardSource, contains('PopScope'));
    expect(guardSource, contains('canPop: false'));

    final router = File('lib/app/routes/app_router.dart').readAsStringSync();
    expect(
      router,
      contains("import '../../core/widgets/root_back_guard.dart';"),
    );
    expect(router, contains('RootBackGuard(child: HomePage())'));
    expect(router, contains('RootBackGuard(child: DiscoverPage())'));
    expect(router, contains('RootBackGuard('));
    expect(router, contains('child: ChatPage('));
    expect(router, contains('RootBackGuard(child: ProfilePage())'));

    final firstLevelPages = [
      'lib/modules/home/home_page.dart',
      'lib/modules/home/discover_page.dart',
      'lib/modules/home/chat_page.dart',
      'lib/modules/home/profile_page.dart',
    ];
    for (final path in firstLevelPages) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('RootBackGuard')), reason: path);
      expect(source, isNot(contains('root_back_guard.dart')), reason: path);
    }

    final secondLevelPages = [
      'lib/modules/profile/edit_profile_page.dart',
      'lib/modules/home/my_moments_page.dart',
      'lib/modules/home/publish_moment_page.dart',
      'lib/modules/home/certified_user_detail_page.dart',
      'lib/modules/im/im_page.dart',
    ];
    for (final path in secondLevelPages) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('RootBackGuard')), reason: path);
    }
  });
}
