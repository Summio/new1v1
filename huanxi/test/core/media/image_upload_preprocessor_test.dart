import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/core/media/image_upload_preprocessor.dart';

void main() {
  group('buildCompressionPlan', () {
    test(
      'returns skip plan when image already fits target bytes and dimensions',
      () {
        final plan = buildCompressionPlan(
          preset: ImageUploadPreset.avatar,
          metadata: const ImageUploadMetadata(
            width: 720,
            height: 720,
            bytesLength: 180 * 1024,
          ),
        );

        expect(plan.shouldCompress, isFalse);
        expect(plan.attempts, isEmpty);
      },
    );

    test('builds resize and quality attempts for oversize moment image', () {
      final plan = buildCompressionPlan(
        preset: ImageUploadPreset.momentImage,
        metadata: const ImageUploadMetadata(
          width: 4032,
          height: 3024,
          bytesLength: 3 * 1024 * 1024,
        ),
      );

      expect(plan.shouldCompress, isTrue);
      expect(plan.attempts, isNotEmpty);
      expect(plan.attempts.first.targetWidth, 1600);
      expect(plan.attempts.first.targetHeight, 1200);
      expect(plan.attempts.take(4).map((attempt) => attempt.quality).toList(), [
        88,
        84,
        80,
        76,
      ]);
    });
  });

  group('ImageUploadPreprocessor', () {
    test(
      'returns original bytes without invoking compressor when image already fits',
      () async {
        final compressor = _FakeImageBytesCompressor([]);
        final preprocessor = ImageUploadPreprocessor(
          dimensionReader: _FakeImageDimensionReader(
            const ImageUploadMetadata(
              width: 800,
              height: 800,
              bytesLength: 190 * 1024,
            ),
          ),
          compressor: compressor,
        );
        final sourceBytes = Uint8List.fromList(List<int>.filled(32, 7));

        final result = await preprocessor.prepareImage(
          bytes: sourceBytes,
          filename: 'avatar.jpg',
          scene: ImageUploadScene.avatar,
        );

        expect(result.bytes, same(sourceBytes));
        expect(result.filename, 'avatar.jpg');
        expect(result.compressed, isFalse);
        expect(compressor.calls, isEmpty);
      },
    );

    test(
      'returns first compressed candidate within preferred target bytes',
      () async {
        final compressor = _FakeImageBytesCompressor([
          Uint8List(930 * 1024),
          Uint8List(840 * 1024),
        ]);
        final preprocessor = ImageUploadPreprocessor(
          dimensionReader: _FakeImageDimensionReader(
            const ImageUploadMetadata(
              width: 4032,
              height: 3024,
              bytesLength: 3 * 1024 * 1024,
            ),
          ),
          compressor: compressor,
        );

        final result = await preprocessor.prepareImage(
          bytes: Uint8List.fromList(List<int>.filled(64, 9)),
          filename: 'moment.heic',
          scene: ImageUploadScene.momentImage,
        );

        expect(result.compressed, isTrue);
        expect(result.bytes.length, 840 * 1024);
        expect(result.filename, 'moment.jpg');
        expect(compressor.formats.take(2), everyElement(CompressFormat.jpeg));
      },
    );

    test(
      'throws when all compressed results still exceed backend max bytes',
      () async {
        final preprocessor = ImageUploadPreprocessor(
          dimensionReader: _FakeImageDimensionReader(
            const ImageUploadMetadata(
              width: 4032,
              height: 3024,
              bytesLength: 4 * 1024 * 1024,
            ),
          ),
          compressor: _FakeImageBytesCompressor([
            Uint8List(1100 * 1024),
            Uint8List(1080 * 1024),
            Uint8List(1060 * 1024),
          ]),
        );

        expect(
          () => preprocessor.prepareImage(
            bytes: Uint8List.fromList(List<int>.filled(64, 8)),
            filename: 'too_large.png',
            scene: ImageUploadScene.momentImage,
          ),
          throwsA(
            isA<ImageUploadPreprocessException>().having(
              (error) => error.message,
              'message',
              '图片过大，请重新选择',
            ),
          ),
        );
      },
    );

    test(
      'transcodes heic to jpg even when bytes already fit the upload budget',
      () async {
        final compressor = _FakeImageBytesCompressor([Uint8List(220 * 1024)]);
        final preprocessor = ImageUploadPreprocessor(
          dimensionReader: _FakeImageDimensionReader(
            const ImageUploadMetadata(
              width: 1080,
              height: 720,
              bytesLength: 220 * 1024,
            ),
          ),
          compressor: compressor,
        );

        final result = await preprocessor.prepareImage(
          bytes: Uint8List.fromList(List<int>.filled(64, 6)),
          filename: 'live.heic',
          scene: ImageUploadScene.avatar,
        );

        expect(result.compressed, isTrue);
        expect(result.filename, 'live.jpg');
        expect(compressor.calls, hasLength(1));
        expect(compressor.formats, [CompressFormat.jpeg]);
      },
    );

    test('keeps png format when compressed for upload', () async {
      final compressor = _FakeImageBytesCompressor([Uint8List(320 * 1024)]);
      final preprocessor = ImageUploadPreprocessor(
        dimensionReader: _FakeImageDimensionReader(
          const ImageUploadMetadata(
            width: 2400,
            height: 2400,
            bytesLength: 2 * 1024 * 1024,
          ),
        ),
        compressor: compressor,
      );

      final result = await preprocessor.prepareImage(
        bytes: Uint8List.fromList(List<int>.filled(64, 4)),
        filename: 'transparent.png',
        scene: ImageUploadScene.avatar,
      );

      expect(result.compressed, isTrue);
      expect(result.filename, 'transparent.png');
      expect(compressor.formats, isNotEmpty);
      expect(compressor.formats, everyElement(CompressFormat.png));
    });

    test(
      'rejects oversized gif instead of silently converting it to jpg',
      () async {
        final preprocessor = ImageUploadPreprocessor(
          dimensionReader: _FakeImageDimensionReader(
            const ImageUploadMetadata(
              width: 1800,
              height: 1800,
              bytesLength: 2 * 1024 * 1024,
            ),
          ),
          compressor: _FakeImageBytesCompressor([Uint8List(280 * 1024)]),
        );

        expect(
          () => preprocessor.prepareImage(
            bytes: Uint8List.fromList(List<int>.filled(64, 3)),
            filename: 'animated.gif',
            scene: ImageUploadScene.momentImage,
          ),
          throwsA(
            isA<ImageUploadPreprocessException>().having(
              (error) => error.message,
              'message',
              'GIF 图片过大，请重新选择',
            ),
          ),
        );
      },
    );
  });
}

class _FakeImageDimensionReader implements ImageDimensionReader {
  const _FakeImageDimensionReader(this.metadata);

  final ImageUploadMetadata metadata;

  @override
  Future<ImageUploadMetadata> read(Uint8List bytes) async => metadata;
}

class _FakeImageBytesCompressor implements ImageBytesCompressor {
  _FakeImageBytesCompressor(List<Uint8List> outputs) : _outputs = outputs;

  final List<Uint8List> _outputs;
  final List<ImageCompressionAttempt> calls = <ImageCompressionAttempt>[];
  final List<CompressFormat> formats = <CompressFormat>[];

  @override
  Future<Uint8List?> compress({
    required Uint8List bytes,
    required ImageCompressionAttempt attempt,
    required CompressFormat format,
  }) async {
    calls.add(attempt);
    formats.add(format);
    if (_outputs.isEmpty) return null;
    return _outputs.removeAt(0);
  }
}
