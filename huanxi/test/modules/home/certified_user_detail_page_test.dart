import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/providers/certified_user_provider.dart';
import 'package:huanxi/modules/home/certified_user_detail_page.dart';

Widget _testPage(CertifiedUserInfo certifiedUser) {
  return ProviderScope(
    child: MaterialApp(
      home: CertifiedUserDetailPage(certifiedUser: certifiedUser),
    ),
  );
}

void main() {
  final certifiedUser = CertifiedUserInfo(
    id: 1,
    userId: 1,
    username: '认证用户A',
    coverUrl: 'https://example.com/cover.jpg',
    albumPhotos: const [
      'https://example.com/1.jpg',
      'https://example.com/2.jpg',
      'https://example.com/3.jpg',
    ],
  );

  testWidgets(
    'certified user detail album uses dot indicators instead of photo count',
    (tester) async {
      await tester.pumpWidget(_testPage(certifiedUser));

      expect(find.text('3 张照片'), findsNothing);
      expect(
        find.byKey(const ValueKey('certified_user_album_dot_0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('certified_user_album_dot_1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('certified_user_album_dot_2')),
        findsOneWidget,
      );
    },
  );

  testWidgets('certified user detail album can swipe and open preview', (
    tester,
  ) async {
    await tester.pumpWidget(_testPage(certifiedUser));

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    final firstDotWidth = tester
        .getSize(find.byKey(const ValueKey('certified_user_album_dot_0')))
        .width;
    final secondDotWidth = tester
        .getSize(find.byKey(const ValueKey('certified_user_album_dot_1')))
        .width;
    expect(secondDotWidth, greaterThan(firstDotWidth));

    await tester.tap(
      find.byKey(const ValueKey('certified_user_album_photo_1')),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets(
    'certified user detail album dots stay above profile panel overlap',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));

      await tester.pumpWidget(_testPage(certifiedUser));

      final dotCenter = tester.getCenter(
        find.byKey(const ValueKey('certified_user_album_dot_0')),
      );
      final albumBottom = tester.getBottomLeft(find.byType(PageView)).dy;

      expect(albumBottom - dotCenter.dy, greaterThan(44));

      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });
    },
  );

  testWidgets('certified user detail shows moments section', (tester) async {
    await tester.pumpWidget(_testPage(certifiedUser));

    expect(find.text('动态'), findsOneWidget);
  });

  testWidgets('certified user detail shows user id', (tester) async {
    await tester.pumpWidget(_testPage(certifiedUser));

    expect(find.text('ID: 1'), findsOneWidget);
  });

  testWidgets('certified user detail has copy user id button', (tester) async {
    await tester.pumpWidget(_testPage(certifiedUser));

    expect(
      find.byKey(const ValueKey('certified_user_id_copy_button')),
      findsOneWidget,
    );
  });

  test('certified user detail call button keeps icon and price only', () {
    final page = File(
      'lib/modules/home/certified_user_detail_page.dart',
    ).readAsStringSync();

    expect(page, contains('Icons.videocam'));
    expect(page, contains('_formatCallPrice('));
    expect(page, contains('certifiedUser.callPrice'));
    expect(page, contains('tokenNames.coinName'));
    expect(page, isNot(contains('立即通话')));
    expect(page, isNot(contains('理解通话')));
    expect(page, isNot(contains(r'(${_formatCallPrice')));
  });
}
