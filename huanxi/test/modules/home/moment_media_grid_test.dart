import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:huanxi/modules/home/moment_media_grid.dart';
import 'package:huanxi/services/moment_service.dart';

void main() {
  testWidgets('single video tile should fill available width on first frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 320,
              child: MomentMediaGrid(
                mediaList: [
                  MomentMedia(
                    id: 1,
                    url: 'https://example.com/video.mp4',
                    mediaType: 2,
                    coverUrl: 'https://example.com/cover.jpg',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final target = find.byType(ClipRRect).first;
    final size = tester.getSize(target);
    final topLeft = tester.getTopLeft(target);

    expect(size.width, 320);
    expect(topLeft.dx, 0);
  });

  testWidgets('mixed media video tile should stay left-aligned on first frame', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: MomentMediaGrid(
                mediaList: [
                  MomentMedia(
                    id: 1,
                    url: 'https://example.com/image.jpg',
                    mediaType: 1,
                  ),
                  MomentMedia(
                    id: 2,
                    url: 'https://example.com/video.mp4',
                    mediaType: 2,
                    coverUrl: 'https://example.com/cover.jpg',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final videoPlayIcon = find.byIcon(Icons.play_arrow);
    final videoClip = find.ancestor(
      of: videoPlayIcon,
      matching: find.byType(ClipRRect),
    );

    final videoLeft = tester.getTopLeft(videoClip.first).dx;
    expect(videoLeft, 0);

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
  });

  testWidgets('mixed media video placeholder should be left-aligned', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: MomentMediaGrid(
                mediaList: [
                  MomentMedia(
                    id: 1,
                    url: 'https://example.com/image.jpg',
                    mediaType: 1,
                  ),
                  MomentMedia(
                    id: 2,
                    url: 'https://example.com/video.mp4',
                    mediaType: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final videoPlayIcon = find.byIcon(Icons.play_arrow);
    final videoClip = find.ancestor(
      of: videoPlayIcon,
      matching: find.byType(ClipRRect),
    );

    final videoLeft = tester.getTopLeft(videoClip.first).dx;
    expect(videoLeft, 0);

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
  });
}
