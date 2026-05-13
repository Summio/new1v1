import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/modules/home/moment_image_preview_page.dart';
import 'package:photo_view/photo_view.dart';
import 'dart:io';

void main() {
  PhotoViewController previewController(WidgetTester tester) {
    final viewer = tester.widget<PhotoView>(find.byType(PhotoView));
    return viewer.controller! as PhotoViewController;
  }

  ScaleStateCycle previewScaleStateCycle(WidgetTester tester) {
    final viewer = tester.widget<PhotoView>(find.byType(PhotoView));
    return viewer.scaleStateCycle!;
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

    expect(pageView.controller?.page, moreOrLessEquals(2));
  });

  testWidgets('image preview double tap cycle toggles zoom and reset', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MomentImagePreviewPage(imageUrl: 'https://example.com/1.jpg'),
      ),
    );

    final controller = previewController(tester);
    final scaleStateCycle = previewScaleStateCycle(tester);

    expect(
      scaleStateCycle(PhotoViewScaleState.initial),
      PhotoViewScaleState.zoomedIn,
    );
    expect(controller.scale, moreOrLessEquals(2.5));

    expect(
      scaleStateCycle(PhotoViewScaleState.zoomedIn),
      PhotoViewScaleState.initial,
    );
    expect(controller.scale, moreOrLessEquals(1.0));
  });

  testWidgets('image preview double tap resets any enlarged real scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MomentImagePreviewPage(imageUrl: 'https://example.com/1.jpg'),
      ),
    );

    final controller = previewController(tester);
    final scaleStateCycle = previewScaleStateCycle(tester);

    controller.scale = 1.1;

    expect(
      scaleStateCycle(PhotoViewScaleState.zoomedIn),
      PhotoViewScaleState.initial,
    );
    expect(controller.scale, moreOrLessEquals(1.0));
  });

  testWidgets('image preview keeps PhotoView pinch gestures enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MomentImagePreviewPage(imageUrl: 'https://example.com/1.jpg'),
      ),
    );

    final viewer = tester.widget<PhotoView>(find.byType(PhotoView));
    expect(viewer.disableGestures, isNot(true));
    expect(viewer.minScale, PhotoViewComputedScale.contained);
    expect(viewer.initialScale, PhotoViewComputedScale.contained);
    expect(viewer.maxScale, PhotoViewComputedScale.contained * 4.0);
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
    'image preview uses PhotoView for pinch zoom and two-state double tap',
    () {
      final source = File(
        'lib/modules/home/moment_image_preview_page.dart',
      ).readAsStringSync();

      expect(source, contains('static const double _doubleTapScale = 2.5;'));
      expect(source, contains('PhotoView('));
      expect(source, contains('PhotoViewController'));
      expect(source, contains('PhotoViewScaleStateController'));
      expect(source, contains('scaleStateCycle: _scaleStateCycle'));
      expect(source, contains('currentScale > _minScale + _scaleTolerance'));
      expect(source, contains('PhotoViewScaleState.initial'));
      expect(source, contains('PhotoViewScaleState.zoomedIn'));
      expect(source, contains('PhotoViewComputedScale.contained * 4.0'));
      expect(source, contains('_resolvedInitialScale() * _doubleTapScale'));
      expect(source, isNot(contains('_nextDoubleTapScale')));
      expect(source, isNot(contains('TransformationController')));
      expect(source, isNot(contains('_clampMatrix')));
      expect(source, isNot(contains('static const double _maxScale = 4.0;')));
    },
  );
}
