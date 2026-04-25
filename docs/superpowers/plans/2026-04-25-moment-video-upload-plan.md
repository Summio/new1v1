# 动态视频上传规则收敛 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将动态视频上传规则收敛到“前端限制 10 秒、仅在超过 8MB 时压缩、后端仅校验视频大小 8MB 和封面 1MB”，并保持现有动态图片上传与视频封面链路稳定。

**Architecture:** Flutter 端新增独立的视频预处理器，统一负责视频元数据读取、10 秒时长拦截、超过 8MB 时压缩以及错误文案；发布动态页面只消费预处理结果，不再自行拼接散落规则。后端继续复用 `upload_files.py` 的统一上传校验思路，新增视频校验入口，把 `/api/v1/app/moment/upload` 的视频主文件限制从 `100MB` 收紧到 `8MB`，不增加真实时长校验；视频封面继续走现有图片 `<= 1MB` 预处理与校验链路。

**Tech Stack:** Flutter + `video_compress` + `flutter_test` + FastAPI + pytest + ruff

---

## File Map

- Create: `huanxi/lib/core/media/video_upload_preprocessor.dart`
- Create: `huanxi/test/core/media/video_upload_preprocessor_test.dart`
- Modify: `huanxi/pubspec.yaml`
- Modify: `huanxi/lib/modules/home/publish_moment_page.dart`
- Modify: `backend/app/utils/upload_files.py`
- Create: `backend/tests/test_upload_video_helpers.py`
- Modify: `backend/app/api/v1/app/moment.py`

---

### Task 1: 为前端视频预处理规则写失败测试

**Files:**
- Create: `huanxi/test/core/media/video_upload_preprocessor_test.dart`

- [ ] **Step 1: 写失败测试，锁定 10 秒拦截、8MB 直传上限和压缩回退行为**

```dart
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/core/media/video_upload_preprocessor_test.dart`
Expected: FAIL，提示 `video_upload_preprocessor.dart` 不存在。

### Task 2: 实现前端视频预处理器

**Files:**
- Create: `huanxi/lib/core/media/video_upload_preprocessor.dart`
- Modify: `huanxi/pubspec.yaml`

- [ ] **Step 1: 增加视频压缩依赖**

```yaml
dependencies:
  video_compress: ^3.1.4
```

- [ ] **Step 2: 实现可测试的视频预处理器，统一 10 秒与 8MB 规则**

```dart
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
    final mediaInfo = await VideoCompress.compressVideo(
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
    await VideoCompress.deleteAllCache();

    return CompressedVideoResult(bytes: bytes, filename: filename);
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
  final separatorIndex = slashIndex > backslashIndex ? slashIndex : backslashIndex;
  return separatorIndex >= 0 ? normalized.substring(separatorIndex + 1) : normalized;
}
```

- [ ] **Step 3: 运行测试确认通过**

Run: `flutter test test/core/media/video_upload_preprocessor_test.dart`
Expected: PASS

### Task 3: 接入动态发布页的视频选择链路

**Files:**
- Modify: `huanxi/lib/modules/home/publish_moment_page.dart`

- [ ] **Step 1: 增加视频处理中状态，并把入口文案改为 10 秒**

```dart
class _PublishMomentPageState extends ConsumerState<PublishMomentPage> {
  final TextEditingController _contentController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  final List<_MediaItem> _selectedMedias = [];
  final List<int> _uploadedMediaIds = [];
  final bool _isUploading = false;
  bool _isPublishing = false;
  bool _isPreparingVideo = false;
}
```

```dart
if (!hasImage && !hasVideo)
  _AddMediaButton(
    icon: Icons.videocam_outlined,
    label: '视频（≤10s）',
    onTap: () => _pickVideo(),
  ),
```

- [ ] **Step 2: 在选中视频后先跑预处理，再用预处理后的时长驱动封面选择**

```dart
Future<void> _pickVideo() async {
  if (_isPreparingVideo) return;

  try {
    final video = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 10),
    );
    if (video == null) return;

    setState(() {
      _isPreparingVideo = true;
    });

    final preparedVideo = await VideoUploadPreprocessor.instance.prepareVideo(
      path: video.path,
      filename: video.name,
    );

    final cover = await _selectVideoCover(
      videoPath: video.path,
      duration: Duration(milliseconds: preparedVideo.durationMs),
    );
    if (cover == null || cover.bytes.isEmpty) {
      _showToast('未选择封面，不能发布视频动态');
      return;
    }

    if (!mounted) return;
    setState(() {
      _selectedMedias.add(
        _MediaItem(
          path: video.path,
          bytes: preparedVideo.bytes,
          mediaType: 2,
          name: preparedVideo.filename,
          durationSeconds: (preparedVideo.durationMs / 1000).ceil(),
          coverBytes: cover.bytes,
          coverName: 'cover_${DateTime.now().millisecondsSinceEpoch}.jpg',
          coverTimeMs: cover.timeMs,
        ),
      );
    });
  } on VideoUploadPreprocessException catch (e) {
    _showToast(e.message);
  } catch (_) {
    _showToast('选择视频失败');
  } finally {
    if (mounted) {
      setState(() {
        _isPreparingVideo = false;
      });
    }
  }
}
```

- [ ] **Step 3: 引入视频预处理器 import，并移除选择阶段对原始视频字节的直接读取**

```dart
import '../../core/media/video_upload_preprocessor.dart';
```

- [ ] **Step 4: 在媒体区域给出处理中反馈，避免压缩时像卡死**

```dart
if (_isPreparingVideo) ...[
  const SizedBox(height: 12),
  Row(
    children: const [
      SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      SizedBox(width: 8),
      Text(
        '视频处理中，请稍候',
        style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
      ),
    ],
  ),
],
```

- [ ] **Step 5: 运行页面相关测试或至少运行媒体预处理测试**

Run: `flutter test test/core/media/video_upload_preprocessor_test.dart`
Expected: PASS

### Task 4: 为后端视频大小限制写失败测试

**Files:**
- Create: `backend/tests/test_upload_video_helpers.py`

- [ ] **Step 1: 写失败测试，锁定统一 8MB 视频限制与后缀校验**

```python
from io import BytesIO

import pytest
from fastapi import UploadFile

from app.utils.upload_files import (
    VIDEO_MAX_BYTES,
    UploadValidationError,
    read_validated_video_upload,
)


@pytest.mark.asyncio
async def test_read_validated_video_upload_rejects_oversized_video() -> None:
    upload = UploadFile(
        file=BytesIO(b"a" * (VIDEO_MAX_BYTES + 1)),
        filename="too-large.mp4",
    )

    with pytest.raises(UploadValidationError) as exc:
        await read_validated_video_upload(
            upload,
            allowed_suffixes={".mp4", ".mov"},
            invalid_suffix_message="仅支持 mp4/mov",
        )

    assert exc.value.message == "视频不能超过8MB"


@pytest.mark.asyncio
async def test_read_validated_video_upload_rejects_invalid_suffix() -> None:
    upload = UploadFile(file=BytesIO(b"avi-bytes"), filename="bad.avi")

    with pytest.raises(UploadValidationError) as exc:
        await read_validated_video_upload(
            upload,
            allowed_suffixes={".mp4", ".mov"},
            invalid_suffix_message="仅支持 mp4/mov",
        )

    assert exc.value.message == "仅支持 mp4/mov"
```

- [ ] **Step 2: 运行测试确认失败**

Run: `.\venv\Scripts\python -m pytest -vv -s tests/test_upload_video_helpers.py`
Expected: FAIL，提示 `read_validated_video_upload` 或 `VIDEO_MAX_BYTES` 未定义。

### Task 5: 实现后端视频限制并接入动态上传接口

**Files:**
- Modify: `backend/app/utils/upload_files.py`
- Modify: `backend/app/api/v1/app/moment.py`

- [ ] **Step 1: 在公共上传工具中新增视频大小常量和视频校验入口**

```python
IMAGE_MAX_BYTES = 1 * 1024 * 1024
VIDEO_MAX_BYTES = 8 * 1024 * 1024


async def read_validated_video_upload(
    file: UploadFile,
    *,
    allowed_suffixes: set[str],
    invalid_suffix_message: str,
) -> tuple[str, bytes]:
    return await read_validated_upload_file(
        file,
        allowed_suffixes=allowed_suffixes,
        max_bytes=VIDEO_MAX_BYTES,
        invalid_suffix_message=invalid_suffix_message,
        too_large_message="视频不能超过8MB",
    )
```

- [ ] **Step 2: 将 `/app/moment/upload` 的视频主文件改为复用公共视频校验工具，移除本地 `100MB` 常量**

```python
from app.utils.upload_files import (
    UploadValidationError,
    read_validated_image_upload,
    read_validated_video_upload,
    save_upload_content,
)
```

```python
elif media_type == 2:
    if cover_file is None or not cover_file.filename:
        return Fail(code=400, msg="视频必须选择封面")
    try:
        suffix, content = await read_validated_video_upload(
            file,
            allowed_suffixes=_ALLOWED_VIDEO_SUFFIX,
            invalid_suffix_message="仅支持 mp4/mov",
        )
    except UploadValidationError as exc:
        return Fail(code=exc.code, msg=exc.message)
```

- [ ] **Step 3: 保持封面图继续复用现有图片 1MB 限制，不增加时长校验**

```python
if media_type == 2 and cover_file is not None:
    try:
        cover_suffix, cover_content = await read_validated_image_upload(
            cover_file,
            allowed_suffixes=_ALLOWED_IMAGE_SUFFIX,
            invalid_suffix_message="封面仅支持 jpg/jpeg/png/gif/webp",
        )
    except UploadValidationError as exc:
        if exc.message == "图片不能超过1MB":
            return Fail(code=exc.code, msg="封面不能超过1MB")
        if exc.message == "文件为空":
            return Fail(code=exc.code, msg="封面文件为空")
        return Fail(code=exc.code, msg=exc.message)
```

- [ ] **Step 4: 运行测试确认通过**

Run: `.\venv\Scripts\python -m pytest -vv -s tests/test_upload_video_helpers.py`
Expected: PASS

### Task 6: 端到端定向验证

**Files:**
- Test: `huanxi/test/core/media/video_upload_preprocessor_test.dart`
- Test: `backend/tests/test_upload_video_helpers.py`

- [ ] **Step 1: 运行 Flutter 视频预处理测试**

Run: `flutter test test/core/media/video_upload_preprocessor_test.dart`
Expected: PASS

- [ ] **Step 2: 运行后端上传限制测试**

Run: `.\venv\Scripts\python -m pytest -vv -s tests/test_upload_video_helpers.py tests/test_upload_image_helpers.py`
Expected: PASS

- [ ] **Step 3: 运行本次改动相关静态检查**

Run: `.\venv\Scripts\python -m ruff check app/utils/upload_files.py app/api/v1/app/moment.py tests/test_upload_video_helpers.py`
Expected: `All checks passed!`

- [ ] **Step 4: 运行 Flutter 定向静态检查**

Run: `dart analyze lib/core/media/video_upload_preprocessor.dart lib/modules/home/publish_moment_page.dart test/core/media/video_upload_preprocessor_test.dart`
Expected: 仅允许出现当前仓库已有的无关 `info`，不出现新增 `error`
