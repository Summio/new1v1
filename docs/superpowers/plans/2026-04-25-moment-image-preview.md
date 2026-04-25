# 动态图片全屏预览 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 点击动态中的图片时全屏放大查看，支持捏合缩放，点击任意位置关闭。

**Architecture:** 新建 `MomentImagePreviewPage` 全屏页面，使用 Flutter 内置 `InteractiveViewer` 实现缩放，无需第三方依赖。`MomentCard` 的 `onTap` 回调接入预览页。

**Tech Stack:** Flutter + InteractiveViewer + MaterialPageRoute

---

## Task 1: 创建 MomentImagePreviewPage

**Files:**
- Create: `huanxi/lib/modules/home/moment_image_preview_page.dart`

- [ ] **Step 1: 创建文件，写入完整实现**

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 动态图片全屏预览页
/// 支持捏合缩放，点击任意位置关闭
class MomentImagePreviewPage extends StatefulWidget {
  final String imageUrl;

  const MomentImagePreviewPage({super.key, required this.imageUrl});

  @override
  State<MomentImagePreviewPage> createState() => _MomentImagePreviewPageState();
}

class _MomentImagePreviewPageState extends State<MomentImagePreviewPage> {
  @override
  void initState() {
    super.initState();
    // 隐藏状态栏和导航栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
    // 恢复状态栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: _buildImage(),
              ),
            ),
            // 左上角关闭按钮（可选，备用关闭方式）
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (widget.imageUrl.startsWith('/uploads/')) {
      return Image.file(
        File(widget.imageUrl),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _errorPlaceholder(),
      );
    }
    return Image.network(
      widget.imageUrl,
      fit: BoxFit.contain,
      loadingBuilder: (_, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded /
                    loadingProgress.expectedTotalBytes!
                : null,
            color: Colors.white,
          ),
        );
      },
      errorBuilder: (_, __, ___) => _errorPlaceholder(),
    );
  }

  Widget _errorPlaceholder() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
        SizedBox(height: 8),
        Text('图片加载失败', style: TextStyle(color: Colors.white54)),
      ],
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add huanxi/lib/modules/home/moment_image_preview_page.dart
git commit -m "feat(moments): add MomentImagePreviewPage with pinch-to-zoom"
```

---

## Task 2: 在 MomentCard 中接入预览页

**Files:**
- Modify: `huanxi/lib/modules/home/moment_card.dart`

先读取当前文件确认 onTap 接入点位置。

- [ ] **Step 1: 添加 import**

在 `moment_card.dart` 顶部添加：

```dart
import 'moment_image_preview_page.dart';
```

- [ ] **Step 2: 修改 _buildMedia 方法，在 onTap 中打开预览页**

找到 `_buildMedia` 方法中 `MomentMediaGrid` 的 `onTap` 回调，改为：

```dart
onTap: (index, media) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MomentImagePreviewPage(imageUrl: media.url),
    ),
  );
},
```

并删除原有的 `// TODO: 点击打开媒体预览` 注释。

- [ ] **Step 3: 运行 Flutter analyze 验证**

Run: `cd D:/1v1/new1v1/huanxi && flutter analyze lib/modules/home/moment_card.dart lib/modules/home/moment_image_preview_page.dart`
Expected: 无错误

- [ ] **Step 4: Commit**

```bash
git add huanxi/lib/modules/home/moment_card.dart
git commit -m "feat(moments): hook image preview to MomentCard onTap"
```

---

## 验证

手动测试流程：
1. 打开发现页或我的动态页
2. 点击任意动态中的图片
3. 确认图片全屏黑色背景展示，状态栏已隐藏
4. 双指捏合放大/缩小，确认缩放生效
5. 点击任意位置，确认预览关闭，状态栏恢复
6. 切换其他动态图片，确认每张都能正常打开预览
