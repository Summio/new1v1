import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/app/providers/anchor_provider.dart';
import 'package:huanxi/modules/home/anchor_detail_page.dart';

void main() {
  final anchor = AnchorInfo(
    id: 1,
    userId: 1,
    username: '主播A',
    coverUrl: 'https://example.com/cover.jpg',
    albumPhotos: const [
      'https://example.com/1.jpg',
      'https://example.com/2.jpg',
      'https://example.com/3.jpg',
    ],
  );

  testWidgets(
    'anchor detail album uses dot indicators instead of photo count',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: AnchorDetailPage(anchor: anchor)),
      );

      expect(find.text('3 张照片'), findsNothing);
      expect(find.byKey(const ValueKey('anchor_album_dot_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('anchor_album_dot_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('anchor_album_dot_2')), findsOneWidget);
    },
  );

  testWidgets('anchor detail album can swipe and open preview', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AnchorDetailPage(anchor: anchor)),
    );

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    final firstDotWidth = tester
        .getSize(find.byKey(const ValueKey('anchor_album_dot_0')))
        .width;
    final secondDotWidth = tester
        .getSize(find.byKey(const ValueKey('anchor_album_dot_1')))
        .width;
    expect(secondDotWidth, greaterThan(firstDotWidth));

    await tester.tap(find.byKey(const ValueKey('anchor_album_photo_1')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('anchor detail album dots stay above profile panel overlap', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));

    await tester.pumpWidget(
      MaterialApp(home: AnchorDetailPage(anchor: anchor)),
    );

    final dotCenter = tester.getCenter(
      find.byKey(const ValueKey('anchor_album_dot_0')),
    );
    final albumBottom = tester.getBottomLeft(find.byType(PageView)).dy;

    expect(albumBottom - dotCenter.dy, greaterThan(44));

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
  });

  testWidgets('anchor detail shows moments section', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AnchorDetailPage(anchor: anchor)),
    );

    expect(find.text('动态'), findsOneWidget);
  });

  testWidgets('anchor detail shows user id', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AnchorDetailPage(anchor: anchor)),
    );

    expect(find.text('ID: 1'), findsOneWidget);
  });

  testWidgets('anchor detail has copy user id button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AnchorDetailPage(anchor: anchor)),
    );

    expect(
      find.byKey(const ValueKey('anchor_user_id_copy_button')),
      findsOneWidget,
    );
  });
}
