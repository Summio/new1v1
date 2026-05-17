import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first-level tab routes use MainShell root back guard only', () {
    final guard = File('lib/core/widgets/root_back_guard.dart');
    expect(guard.existsSync(), isFalse);

    final router = File('lib/app/routes/app_router.dart').readAsStringSync();
    expect(
      router,
      isNot(contains("import '../../core/widgets/root_back_guard.dart';")),
    );
    expect(router, isNot(contains('RootBackGuard')));
    expect(router, contains('MainShell(child: child)'));
    expect(router, contains('NoTransitionPage(child: HomePage())'));
    expect(router, contains('NoTransitionPage(child: DiscoverPage())'));
    expect(router, contains('child: ChatPage('));
    expect(router, contains('NoTransitionPage(child: ProfilePage())'));

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
      expect(source, isNot(contains('PopScope')), reason: path);
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

    final shell = File('lib/modules/home/main_shell.dart').readAsStringSync();
    expect(shell, contains('PopScope'));
    expect(shell, contains('_shouldBlockRootBack'));
  });
}
