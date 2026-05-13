import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/modules/home/moment_image_preview_page.dart';
import 'dart:io';

void main() {
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
}
