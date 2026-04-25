import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';

enum ImageUploadScene { avatar, momentImage, momentCover }

enum ImageFileKind { jpeg, png, webp, gif, heic, heif, unknown }

class ImageUploadPreset {
  const ImageUploadPreset({
    required this.targetBytes,
    required this.backendMaxBytes,
    required this.maxLongEdge,
    required this.minLongEdge,
    required this.qualities,
  });

  final int targetBytes;
  final int backendMaxBytes;
  final int maxLongEdge;
  final int minLongEdge;
  final List<int> qualities;

  static const ImageUploadPreset avatar = ImageUploadPreset(
    targetBytes: 300 * 1024,
    backendMaxBytes: 1024 * 1024,
    maxLongEdge: 1080,
    minLongEdge: 720,
    qualities: <int>[88, 84, 80],
  );

  static const ImageUploadPreset momentImage = ImageUploadPreset(
    targetBytes: 850 * 1024,
    backendMaxBytes: 1024 * 1024,
    maxLongEdge: 1600,
    minLongEdge: 1120,
    qualities: <int>[88, 84, 80, 76],
  );

  static const ImageUploadPreset momentCover = ImageUploadPreset(
    targetBytes: 400 * 1024,
    backendMaxBytes: 1024 * 1024,
    maxLongEdge: 1280,
    minLongEdge: 720,
    qualities: <int>[88, 84, 80, 76],
  );

  static ImageUploadPreset fromScene(ImageUploadScene scene) {
    switch (scene) {
      case ImageUploadScene.avatar:
        return avatar;
      case ImageUploadScene.momentImage:
        return momentImage;
      case ImageUploadScene.momentCover:
        return momentCover;
    }
  }
}

class ImageUploadMetadata {
  const ImageUploadMetadata({
    required this.width,
    required this.height,
    required this.bytesLength,
  });

  final int width;
  final int height;
  final int bytesLength;

  int get longestEdge => math.max(width, height);
}

class ImageCompressionAttempt {
  const ImageCompressionAttempt({
    required this.targetWidth,
    required this.targetHeight,
    required this.quality,
  });

  final int targetWidth;
  final int targetHeight;
  final int quality;
}

class ImageCompressionPlan {
  const ImageCompressionPlan({
    required this.shouldCompress,
    this.attempts = const <ImageCompressionAttempt>[],
  });

  const ImageCompressionPlan.skip()
    : shouldCompress = false,
      attempts = const <ImageCompressionAttempt>[];

  final bool shouldCompress;
  final List<ImageCompressionAttempt> attempts;
}

class PreparedUploadImage {
  const PreparedUploadImage({
    required this.bytes,
    required this.filename,
    required this.compressed,
  });

  final Uint8List bytes;
  final String filename;
  final bool compressed;
}

class ImageUploadPreprocessException implements Exception {
  const ImageUploadPreprocessException(this.message);

  final String message;

  @override
  String toString() => 'ImageUploadPreprocessException: $message';
}

abstract class ImageDimensionReader {
  const ImageDimensionReader();

  Future<ImageUploadMetadata> read(Uint8List bytes);
}

abstract class ImageBytesCompressor {
  const ImageBytesCompressor();

  Future<Uint8List?> compress({
    required Uint8List bytes,
    required ImageCompressionAttempt attempt,
    required CompressFormat format,
  });
}

class FlutterImageDimensionReader implements ImageDimensionReader {
  const FlutterImageDimensionReader();

  @override
  Future<ImageUploadMetadata> read(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        return ImageUploadMetadata(
          width: frame.image.width,
          height: frame.image.height,
          bytesLength: bytes.length,
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}

class FlutterImageBytesCompressor implements ImageBytesCompressor {
  const FlutterImageBytesCompressor();

  @override
  Future<Uint8List?> compress({
    required Uint8List bytes,
    required ImageCompressionAttempt attempt,
    required CompressFormat format,
  }) {
    return FlutterImageCompress.compressWithList(
      bytes,
      minWidth: attempt.targetWidth,
      minHeight: attempt.targetHeight,
      quality: attempt.quality,
      format: format,
      keepExif: false,
      autoCorrectionAngle: true,
    );
  }
}

class ImageUploadPreprocessor {
  ImageUploadPreprocessor({
    ImageDimensionReader? dimensionReader,
    ImageBytesCompressor? compressor,
  }) : _dimensionReader =
           dimensionReader ?? const FlutterImageDimensionReader(),
       _compressor = compressor ?? const FlutterImageBytesCompressor();

  static final ImageUploadPreprocessor instance = ImageUploadPreprocessor();

  final ImageDimensionReader _dimensionReader;
  final ImageBytesCompressor _compressor;

  Future<PreparedUploadImage> prepareImage({
    required List<int> bytes,
    required String filename,
    required ImageUploadScene scene,
  }) async {
    final normalizedBytes = _normalizeBytes(bytes);
    final sourceKind = _detectImageFileKind(filename);
    if (!_sceneSupportsFileKind(scene, sourceKind)) {
      throw ImageUploadPreprocessException(_unsupportedImageMessage(scene));
    }

    final preset = ImageUploadPreset.fromScene(scene);
    final metadata = await _dimensionReader.read(normalizedBytes);
    final plan = buildCompressionPlan(preset: preset, metadata: metadata);
    final needsCompatibleTranscode = _requiresCompatibleTranscode(sourceKind);

    if (!plan.shouldCompress && !needsCompatibleTranscode) {
      return PreparedUploadImage(
        bytes: normalizedBytes,
        filename: _normalizeOriginalFilename(filename),
        compressed: false,
      );
    }

    final targetKind = _resolveEncodedFileKind(
      sourceKind: sourceKind,
      isReencoding: plan.shouldCompress || needsCompatibleTranscode,
    );
    if (targetKind == null) {
      throw ImageUploadPreprocessException(
        _reencodeUnsupportedMessage(sourceKind),
      );
    }

    final attempts = plan.shouldCompress
        ? plan.attempts
        : _buildFormatNormalizationAttempts(
            metadata: metadata,
            qualities: preset.qualities,
          );
    final format = _compressFormatForKind(targetKind);
    final outputFilename = _filenameForKind(filename, targetKind);

    Uint8List? bestCandidate;
    for (final attempt in attempts) {
      final candidate = await _compressor.compress(
        bytes: normalizedBytes,
        attempt: attempt,
        format: format,
      );
      if (candidate == null || candidate.isEmpty) continue;

      if (candidate.length <= preset.targetBytes) {
        return PreparedUploadImage(
          bytes: candidate,
          filename: outputFilename,
          compressed: true,
        );
      }

      if (candidate.length <= preset.backendMaxBytes &&
          (bestCandidate == null || candidate.length < bestCandidate.length)) {
        bestCandidate = candidate;
      }
    }

    if (bestCandidate != null) {
      return PreparedUploadImage(
        bytes: bestCandidate,
        filename: outputFilename,
        compressed: true,
      );
    }

    if (!needsCompatibleTranscode &&
        metadata.bytesLength <= preset.backendMaxBytes &&
        metadata.longestEdge <= preset.maxLongEdge) {
      return PreparedUploadImage(
        bytes: normalizedBytes,
        filename: _normalizeOriginalFilename(filename),
        compressed: false,
      );
    }

    if (needsCompatibleTranscode) {
      throw const ImageUploadPreprocessException('图片处理失败，请重新选择');
    }

    throw const ImageUploadPreprocessException('图片过大，请重新选择');
  }
}

ImageCompressionPlan buildCompressionPlan({
  required ImageUploadPreset preset,
  required ImageUploadMetadata metadata,
}) {
  if (metadata.bytesLength <= preset.targetBytes &&
      metadata.longestEdge <= preset.maxLongEdge) {
    return const ImageCompressionPlan.skip();
  }

  final startLongEdge = math.min(metadata.longestEdge, preset.maxLongEdge);
  final edgeAttempts = _buildLongEdgeAttempts(
    preset: preset,
    metadata: metadata,
    startLongEdge: startLongEdge,
  );
  final attempts = <ImageCompressionAttempt>[];

  for (final edge in edgeAttempts) {
    final scaled = _scaleToLongEdge(
      width: metadata.width,
      height: metadata.height,
      targetLongEdge: edge,
    );
    for (final quality in preset.qualities) {
      attempts.add(
        ImageCompressionAttempt(
          targetWidth: scaled.width,
          targetHeight: scaled.height,
          quality: quality,
        ),
      );
    }
  }

  return ImageCompressionPlan(shouldCompress: true, attempts: attempts);
}

class _ScaledDimensions {
  const _ScaledDimensions({required this.width, required this.height});

  final int width;
  final int height;
}

List<int> _buildLongEdgeAttempts({
  required ImageUploadPreset preset,
  required ImageUploadMetadata metadata,
  required int startLongEdge,
}) {
  final attempts = <int>{startLongEdge};
  final oversizeRatio = metadata.bytesLength / preset.targetBytes;

  if (metadata.longestEdge > preset.maxLongEdge || oversizeRatio > 1.2) {
    attempts.add(_shrinkEdge(startLongEdge, 0.9, preset.minLongEdge));
  }
  if (oversizeRatio > 2.0) {
    attempts.add(_shrinkEdge(startLongEdge, 0.8, preset.minLongEdge));
  }
  if (oversizeRatio > 3.0) {
    attempts.add(_shrinkEdge(startLongEdge, 0.7, preset.minLongEdge));
  }

  final sorted = attempts.toList()..sort((a, b) => b.compareTo(a));
  return sorted;
}

int _shrinkEdge(int source, double factor, int minLongEdge) {
  final next = (source * factor).round();
  return math.max(minLongEdge, next);
}

_ScaledDimensions _scaleToLongEdge({
  required int width,
  required int height,
  required int targetLongEdge,
}) {
  final longestEdge = math.max(width, height);
  if (longestEdge <= targetLongEdge) {
    return _ScaledDimensions(width: width, height: height);
  }

  final scale = targetLongEdge / longestEdge;
  return _ScaledDimensions(
    width: math.max(1, (width * scale).round()),
    height: math.max(1, (height * scale).round()),
  );
}

Uint8List _normalizeBytes(List<int> bytes) {
  return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
}

List<ImageCompressionAttempt> _buildFormatNormalizationAttempts({
  required ImageUploadMetadata metadata,
  required List<int> qualities,
}) {
  return qualities
      .map(
        (quality) => ImageCompressionAttempt(
          targetWidth: metadata.width,
          targetHeight: metadata.height,
          quality: quality,
        ),
      )
      .toList();
}

String _normalizeOriginalFilename(String filename) {
  final basename = _basename(filename);
  return basename.isEmpty ? 'image_upload.jpg' : basename;
}

String _filenameForKind(String filename, ImageFileKind kind) {
  final basename = _basename(filename);
  final dotIndex = basename.lastIndexOf('.');
  final stem = dotIndex > 0 ? basename.substring(0, dotIndex) : basename;
  final normalizedStem = stem.trim().isEmpty ? 'image_upload' : stem.trim();
  return '$normalizedStem${_extensionForKind(kind)}';
}

ImageFileKind _detectImageFileKind(String filename) {
  switch (Pathless.extension(filename)) {
    case '.jpg':
    case '.jpeg':
      return ImageFileKind.jpeg;
    case '.png':
      return ImageFileKind.png;
    case '.webp':
      return ImageFileKind.webp;
    case '.gif':
      return ImageFileKind.gif;
    case '.heic':
      return ImageFileKind.heic;
    case '.heif':
      return ImageFileKind.heif;
    default:
      return ImageFileKind.unknown;
  }
}

bool _sceneSupportsFileKind(ImageUploadScene scene, ImageFileKind kind) {
  switch (scene) {
    case ImageUploadScene.avatar:
      return kind == ImageFileKind.jpeg ||
          kind == ImageFileKind.png ||
          kind == ImageFileKind.webp ||
          kind == ImageFileKind.heic ||
          kind == ImageFileKind.heif;
    case ImageUploadScene.momentImage:
    case ImageUploadScene.momentCover:
      return kind == ImageFileKind.jpeg ||
          kind == ImageFileKind.png ||
          kind == ImageFileKind.webp ||
          kind == ImageFileKind.gif ||
          kind == ImageFileKind.heic ||
          kind == ImageFileKind.heif;
  }
}

bool _requiresCompatibleTranscode(ImageFileKind kind) {
  return kind == ImageFileKind.heic || kind == ImageFileKind.heif;
}

ImageFileKind? _resolveEncodedFileKind({
  required ImageFileKind sourceKind,
  required bool isReencoding,
}) {
  switch (sourceKind) {
    case ImageFileKind.jpeg:
    case ImageFileKind.heic:
    case ImageFileKind.heif:
      return ImageFileKind.jpeg;
    case ImageFileKind.png:
      return ImageFileKind.png;
    case ImageFileKind.webp:
      return ImageFileKind.webp;
    case ImageFileKind.gif:
      return isReencoding ? null : ImageFileKind.gif;
    case ImageFileKind.unknown:
      return null;
  }
}

CompressFormat _compressFormatForKind(ImageFileKind kind) {
  switch (kind) {
    case ImageFileKind.jpeg:
      return CompressFormat.jpeg;
    case ImageFileKind.png:
      return CompressFormat.png;
    case ImageFileKind.webp:
      return CompressFormat.webp;
    case ImageFileKind.gif:
    case ImageFileKind.heic:
    case ImageFileKind.heif:
    case ImageFileKind.unknown:
      throw UnsupportedError('unsupported compress format: $kind');
  }
}

String _extensionForKind(ImageFileKind kind) {
  switch (kind) {
    case ImageFileKind.jpeg:
      return '.jpg';
    case ImageFileKind.png:
      return '.png';
    case ImageFileKind.webp:
      return '.webp';
    case ImageFileKind.gif:
      return '.gif';
    case ImageFileKind.heic:
      return '.heic';
    case ImageFileKind.heif:
      return '.heif';
    case ImageFileKind.unknown:
      return '.jpg';
  }
}

String _unsupportedImageMessage(ImageUploadScene scene) {
  switch (scene) {
    case ImageUploadScene.avatar:
      return '仅支持 jpg/jpeg/png/webp';
    case ImageUploadScene.momentImage:
    case ImageUploadScene.momentCover:
      return '仅支持 jpg/jpeg/png/gif/webp';
  }
}

String _reencodeUnsupportedMessage(ImageFileKind kind) {
  if (kind == ImageFileKind.gif) {
    return 'GIF 图片过大，请重新选择';
  }
  return '图片处理失败，请重新选择';
}

String _basename(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return '';
  final slashIndex = math.max(
    normalized.lastIndexOf('/'),
    normalized.lastIndexOf('\\'),
  );
  return slashIndex >= 0 ? normalized.substring(slashIndex + 1) : normalized;
}

class Pathless {
  static String extension(String value) {
    final basename = _basename(value).toLowerCase();
    final dotIndex = basename.lastIndexOf('.');
    if (dotIndex < 0) {
      return '';
    }
    return basename.substring(dotIndex);
  }
}
