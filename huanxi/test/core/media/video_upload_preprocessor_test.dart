import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/core/media/video_upload_preprocessor.dart';

void main() {
  group('VideoUploadPreprocessor', () {
    test('rejects video longer than 10 seconds', () async {
      final preprocessor = VideoUploadPreprocessor(
        metadataReader: _FakeVideoMetadataReader(
          const VideoUploadMetadata(
            durationMs: 11 * 1000,
            bytesLength: 4 * 1024 * 1024,
          ),
        ),
        fileReader: _FakeVideoFileReader(Uint8List(0)),
        compressor: _FakeVideoCompressor(const <CompressedVideoResult?>[]),
      );

      await expectLater(
        () => preprocessor.prepareVideo(path: '/tmp/a.mp4', filename: 'a.mp4'),
        throwsA(
          isA<VideoUploadPreprocessException>().having(
            (error) => error.message,
            'message',
            '视频时长不能超过10秒',
          ),
        ),
      );
    });

    test('keeps original bytes when video is already within 8MB budget', () async {
      final sourceBytes = Uint8List(6 * 1024 * 1024);
      final compressor = _FakeVideoCompressor(const <CompressedVideoResult?>[]);
      final preprocessor = VideoUploadPreprocessor(
        metadataReader: _FakeVideoMetadataReader(
          const VideoUploadMetadata(
            durationMs: 8 * 1000,
            bytesLength: 6 * 1024 * 1024,
          ),
        ),
        fileReader: _FakeVideoFileReader(sourceBytes),
        compressor: compressor,
      );

      final result = await preprocessor.prepareVideo(
        path: '/tmp/clip.mov',
        filename: 'clip.mov',
      );

      expect(result.bytes, same(sourceBytes));
      expect(result.filename, 'clip.mov');
      expect(result.durationMs, 8 * 1000);
      expect(result.compressed, isFalse);
      expect(compressor.calls, isEmpty);
    });

    test('returns compressed bytes when original video is over 8MB', () async {
      final compressor = _FakeVideoCompressor([
        CompressedVideoResult(
          bytes: Uint8List(5 * 1024 * 1024),
          filename: 'compressed.mp4',
        ),
      ]);
      final preprocessor = VideoUploadPreprocessor(
        metadataReader: _FakeVideoMetadataReader(
          const VideoUploadMetadata(
            durationMs: 10 * 1000,
            bytesLength: 9 * 1024 * 1024,
          ),
        ),
        fileReader: _FakeVideoFileReader(Uint8List(9 * 1024 * 1024)),
        compressor: compressor,
      );

      final result = await preprocessor.prepareVideo(
        path: '/tmp/a.mov',
        filename: 'a.mov',
      );

      expect(result.bytes.length, 5 * 1024 * 1024);
      expect(result.filename, 'compressed.mp4');
      expect(result.durationMs, 10 * 1000);
      expect(result.compressed, isTrue);
      expect(compressor.calls, ['/tmp/a.mov']);
    });

    test('throws when compressed video still exceeds 8MB backend limit', () async {
      final preprocessor = VideoUploadPreprocessor(
        metadataReader: _FakeVideoMetadataReader(
          const VideoUploadMetadata(
            durationMs: 10 * 1000,
            bytesLength: 12 * 1024 * 1024,
          ),
        ),
        fileReader: _FakeVideoFileReader(Uint8List(12 * 1024 * 1024)),
        compressor: _FakeVideoCompressor([
          CompressedVideoResult(
            bytes: Uint8List(9 * 1024 * 1024),
            filename: 'still-too-large.mp4',
          ),
        ]),
      );

      await expectLater(
        () => preprocessor.prepareVideo(path: '/tmp/a.mov', filename: 'a.mov'),
        throwsA(
          isA<VideoUploadPreprocessException>().having(
            (error) => error.message,
            'message',
            '视频不能超过8MB',
          ),
        ),
      );
    });
  });
}

class _FakeVideoMetadataReader implements VideoMetadataReader {
  const _FakeVideoMetadataReader(this.metadata);

  final VideoUploadMetadata metadata;

  @override
  Future<VideoUploadMetadata> read(String path) async => metadata;
}

class _FakeVideoFileReader implements VideoFileReader {
  const _FakeVideoFileReader(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List> read(String path) async => bytes;
}

class _FakeVideoCompressor implements VideoCompressor {
  _FakeVideoCompressor(List<CompressedVideoResult?> outputs)
      : _outputs = outputs.toList();

  final List<CompressedVideoResult?> _outputs;
  final List<String> calls = <String>[];

  @override
  Future<CompressedVideoResult?> compress(String path) async {
    calls.add(path);
    if (_outputs.isEmpty) {
      return null;
    }
    return _outputs.removeAt(0);
  }
}
