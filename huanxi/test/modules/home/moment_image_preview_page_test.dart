import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/modules/home/moment_image_preview_page.dart';
import 'dart:io';

void main() {
  TransformationController previewTransformationController(
    WidgetTester tester,
  ) {
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    return viewer.transformationController!;
  }

  Future<void> doubleTapAt(WidgetTester tester, Offset position) async {
    final first = await tester.createGesture();
    await first.down(position);
    await tester.pump(const Duration(milliseconds: 20));
    await first.up();
    await tester.pump(const Duration(milliseconds: 60));

    final second = await tester.createGesture();
    await second.down(position);
    await tester.pump(const Duration(milliseconds: 20));
    await second.up();
    await tester.pumpAndSettle();
  }

  testWidgets('image preview opens at initial index and swipes within group', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MomentImagePreviewPage(
          imageUrl: 'https://example.com/2.jpg',
          imageUrls: [
            'https://example.com/1.jpg',
            'https://example.com/2.jpg',
            'https://example.com/3.jpg',
          ],
          initialIndex: 1,
        ),
      ),
    );

    final pageView = tester.widget<PageView>(
      find.byKey(const ValueKey('moment_image_preview_page_view')),
    );
    expect(pageView.controller?.initialPage, 1);

    await tester.drag(
      find.byKey(const ValueKey('moment_image_preview_page_view')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    final thirdImage = tester.widget<Image>(
      find.byKey(const ValueKey('moment_image_preview_image_2')),
    );
    expect((thirdImage.image as NetworkImage).url, 'https://example.com/3.jpg');
  });

  testWidgets('image preview double tap reaches 2.5x then 4x then resets', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MomentImagePreviewPage(imageUrl: 'https://example.com/1.jpg'),
      ),
    );

    final controller = previewTransformationController(tester);
    const position = Offset(400, 300);

    await doubleTapAt(tester, position);
    expect(controller.value.getMaxScaleOnAxis(), moreOrLessEquals(2.5));

    await doubleTapAt(tester, position);
    expect(controller.value.getMaxScaleOnAxis(), moreOrLessEquals(4.0));

    await doubleTapAt(tester, position);
    expect(controller.value.getMaxScaleOnAxis(), moreOrLessEquals(1.0));
  });

  testWidgets('image preview still supports manual pinch zoom', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MomentImagePreviewPage(imageUrl: 'https://example.com/1.jpg'),
      ),
    );

    final controller = previewTransformationController(tester);
    final first = await tester.createGesture(pointer: 1);
    final second = await tester.createGesture(pointer: 2);

    await first.down(const Offset(350, 300));
    await second.down(const Offset(450, 300));
    await tester.pump();
    await first.moveTo(const Offset(250, 300));
    await second.moveTo(const Offset(550, 300));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.0));
  });

  test('image preview keeps zoom controllers scoped per page', () {
    final source = File(
      'lib/modules/home/moment_image_preview_page.dart',
    ).readAsStringSync();
    final parentStateSource = source.substring(
      source.indexOf('class _MomentImagePreviewPageState'),
      source.indexOf('class _ZoomableImagePage'),
    );

    expect(source, contains('class _ZoomableImagePage'));
    expect(parentStateSource, isNot(contains('TransformationController')));
  });

  test(
    'image preview double tap cycles through two zoom levels before reset',
    () {
      final source = File(
        'lib/modules/home/moment_image_preview_page.dart',
      ).readAsStringSync();

      expect(source, contains('static const double _doubleTapScale = 2.5;'));
      expect(source, contains('static const double _maxScale = 4.0;'));
      expect(
        source,
        contains('double _nextDoubleTapScale(double currentScale)'),
      );
      expect(
        source,
        contains('final targetScale = _nextDoubleTapScale(currentScale);'),
      );
      expect(source, contains('scale: targetScale'));
      expect(source, contains('_clampMatrix(target, viewport)'));
      expect(source, isNot(contains('if (currentScale > 1.05)')));
    },
  );
}
