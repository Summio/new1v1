import 'dart:io';
import 'dart:typed_data';

import 'package:video_compress/video_compress.dart';

class VideoUploadLimits {
  static const int maxDurationMs = 10 * 1000;
  static const int backendMaxBytes = 8 * 1024 * 1024;
}

class VideoUploadMetadata {
  const VideoUploadMetadata({
    required this.durationMs,
    required this.bytesLength,
  });

  final int durationMs;
  final int bytesLength;
}

class CompressedVideoResult {
  const CompressedVideoResult({
    required this.bytes,
    required this.filename,
  });

  final Uint8List bytes;
  final String filename;
}

class PreparedUploadVideo {
  const PreparedUploadVideo({
    required this.bytes,
    required this.filename,
    required this.durationMs,
    required this.compressed,
  });

  final Uint8List bytes;
  final String filename;
  final int durationMs;
  final bool compressed;
}

class VideoUploadPreprocessException implements Exception {
  const VideoUploadPreprocessException(this.message);

  final String message;

  @override
  String toString() => 'VideoUploadPreprocessException: $message';
}

abstract class VideoMetadataReader {
  const VideoMetadataReader();

  Future<VideoUploadMetadata> read(String path);
}

abstract class VideoFileReader {
  const VideoFileReader();

  Future<Uint8List> read(String path);
}

abstract class VideoCompressor {
  const VideoCompressor();

  Future<CompressedVideoResult?> compress(String path);
}

class FlutterVideoMetadataReader implements VideoMetadataReader {
  const FlutterVideoMetadataReader();

  @override
  Future<VideoUploadMetadata> read(String path) async {
    final info = await VideoCompress.getMediaInfo(path);
    final file = File(path);
    final durationMs = info.duration?.round() ?? 0;
    final bytesLength = info.filesize ?? await file.length();

    return VideoUploadMetadata(
      durationMs: durationMs,
      bytesLength: bytesLength,
    );
  }
}

class FlutterVideoFileReader implements VideoFileReader {
  const FlutterVideoFileReader();

  @override
  Future<Uint8List> read(String path) => File(path).readAsBytes();
}

class FlutterVideoCompressor implements VideoCompressor {
  const FlutterVideoCompressor();

  @override
  Future<CompressedVideoResult?> compress(String path) async {
    MediaInfo? mediaInfo;
    try {
      mediaInfo = await VideoCompress.compressVideo(
        path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
        frameRate: 30,
      );

      final file = mediaInfo?.file;
      if (mediaInfo == null || mediaInfo.isCancel == true || file == null) {
        return null;
      }

      final bytes = await file.readAsBytes();
      final filename = _normalizeCompressedFilename(
        originalFilename: path,
        compressedPath: file.path,
      );
      return CompressedVideoResult(bytes: bytes, filename: filename);
    } finally {
      await VideoCompress.deleteAllCache();
    }
  }
}

class VideoUploadPreprocessor {
  VideoUploadPreprocessor({
    VideoMetadataReader? metadataReader,
    VideoFileReader? fileReader,
    VideoCompressor? compressor,
  }) : _metadataReader =
           metadataReader ?? const FlutterVideoMetadataReader(),
       _fileReader = fileReader ?? const FlutterVideoFileReader(),
       _compressor = compressor ?? const FlutterVideoCompressor();

  static final VideoUploadPreprocessor instance = VideoUploadPreprocessor();

  final VideoMetadataReader _metadataReader;
  final VideoFileReader _fileReader;
  final VideoCompressor _compressor;

  Future<PreparedUploadVideo> prepareVideo({
    required String path,
    required String filename,
  }) async {
    final metadata = await _metadataReader.read(path);
    if (metadata.durationMs > VideoUploadLimits.maxDurationMs) {
      throw const VideoUploadPreprocessException('视频时长不能超过10秒');
    }

    if (metadata.bytesLength <= VideoUploadLimits.backendMaxBytes) {
      final bytes = await _fileReader.read(path);
      return PreparedUploadVideo(
        bytes: bytes,
        filename: _normalizeOriginalFilename(filename),
        durationMs: metadata.durationMs,
        compressed: false,
      );
    }

    final compressed = await _compressor.compress(path);
    if (compressed == null || compressed.bytes.isEmpty) {
      throw const VideoUploadPreprocessException('视频处理失败，请重试');
    }
    if (compressed.bytes.length > VideoUploadLimits.backendMaxBytes) {
      throw const VideoUploadPreprocessException('视频不能超过8MB');
    }

    return PreparedUploadVideo(
      bytes: compressed.bytes,
      filename: compressed.filename,
      durationMs: metadata.durationMs,
      compressed: true,
    );
  }
}

String _normalizeOriginalFilename(String filename) {
  final basename = _basename(filename);
  return basename.isEmpty ? 'video_upload.mp4' : basename;
}

String _normalizeCompressedFilename({
  required String originalFilename,
  required String compressedPath,
}) {
  final compressedName = _basename(compressedPath);
  if (compressedName.isNotEmpty) {
    return compressedName;
  }

  final originalName = _basename(originalFilename);
  final dotIndex = originalName.lastIndexOf('.');
  final stem = dotIndex > 0 ? originalName.substring(0, dotIndex) : originalName;
  final normalizedStem = stem.trim().isEmpty ? 'video_upload' : stem.trim();
  return '$normalizedStem.mp4';
}

String _basename(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return '';
  }

  final slashIndex = normalized.lastIndexOf('/');
  final backslashIndex = normalized.lastIndexOf('\\');
  final separatorIndex = slashIndex > backslashIndex
      ? slashIndex
      : backslashIndex;
  return separatorIndex >= 0
      ? normalized.substring(separatorIndex + 1)
      : normalized;
}
