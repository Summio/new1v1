# App 端图片智能压缩 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Flutter App 端图片上传增加统一的智能压缩预处理，在不破坏现有上传接口的前提下，将头像、动态图片、视频封面稳定控制在后端单图 1MB 限制内，并为后续新增图片入口提供复用能力。

**Architecture:** 新增一个独立的图片上传预处理器，拆分为“纯策略判断”和“平台压缩执行”两层。现有页面不再依赖 `image_picker` 的临时压缩参数，而是在上传服务层统一调用预处理器，分别接入头像上传与动态媒体上传。

**Tech Stack:** Flutter + flutter_test + flutter_image_compress + Dio Multipart 上传

---

### Task 1: 定义策略测试并锁定场景参数

**Files:**
- Create: `huanxi/test/core/media/image_upload_preprocessor_test.dart`

- [ ] **Step 1: 写失败测试，覆盖无需压缩、生成压缩尝试、压缩成功、压缩失败四类行为**

```dart
test('returns original bytes when image already meets limits', () {});
test('builds attempts for oversize moment image', () {});
test('returns first compressed candidate within target bytes', () {});
test('throws when all compressed results still exceed backend limit', () {});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/core/media/image_upload_preprocessor_test.dart`
Expected: FAIL，提示预处理器文件或类型不存在。

### Task 2: 实现统一图片上传预处理器

**Files:**
- Create: `huanxi/lib/core/media/image_upload_preprocessor.dart`
- Modify: `huanxi/pubspec.yaml`

- [ ] **Step 1: 新增场景枚举、参数配置、压缩尝试生成逻辑**

```dart
enum ImageUploadScene { avatar, momentImage, momentCover }

class ImageUploadPreset {
  final int targetBytes;
  final int backendMaxBytes;
  final int maxLongEdge;
  final int minLongEdge;
}
```

- [ ] **Step 2: 包装平台压缩器与尺寸读取器，实现统一预处理入口**

```dart
Future<PreparedUploadImage> prepareImage({
  required List<int> bytes,
  required String filename,
  required ImageUploadScene scene,
})
```

- [ ] **Step 3: 运行测试确认通过**

Run: `flutter test test/core/media/image_upload_preprocessor_test.dart`
Expected: PASS

### Task 3: 接入现有头像与动态上传链路

**Files:**
- Modify: `huanxi/lib/app/providers/auth_provider.dart`
- Modify: `huanxi/lib/services/moment_service.dart`
- Modify: `huanxi/lib/modules/profile/edit_profile_page.dart`
- Modify: `huanxi/lib/modules/home/publish_moment_page.dart`

- [ ] **Step 1: 头像上传前调用统一预处理器**

```dart
final prepared = await ImageUploadPreprocessor.instance.prepareImage(
  bytes: bytes,
  filename: filename,
  scene: ImageUploadScene.avatar,
);
```

- [ ] **Step 2: 动态图片与视频封面上传前调用统一预处理器**

```dart
final prepared = await ImageUploadPreprocessor.instance.prepareImage(
  bytes: bytes,
  filename: filename,
  scene: mediaType == 1
      ? ImageUploadScene.momentImage
      : ImageUploadScene.momentCover,
);
```

- [ ] **Step 3: 移除 `image_picker` 的压缩参数，避免双重压缩**

```dart
await _picker.pickMultiImage();
await _imagePicker.pickImage(source: ImageSource.gallery);
```

### Task 4: 验证回归与稳定性

**Files:**
- Test: `huanxi/test/core/media/image_upload_preprocessor_test.dart`

- [ ] **Step 1: 运行新增单测**

Run: `flutter test test/core/media/image_upload_preprocessor_test.dart`
Expected: PASS

- [ ] **Step 2: 运行 Flutter 静态检查**

Run: `flutter analyze`
Expected: exit 0
