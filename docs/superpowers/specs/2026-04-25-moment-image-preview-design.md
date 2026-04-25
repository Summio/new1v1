# 动态图片全屏预览

**日期：** 2026-04-25
**状态：** 已批准

## 需求

- 点击动态中的图片，全屏放大查看
- 支持捏合缩放（双指放大/缩小）
- 单张单独预览，不支持多图滑动切换
- 点击任意位置关闭预览
- 无打开动画，直接显示

## 设计

### 组件：MomentImagePreviewPage

全屏展示单张图片的页面，路径：`huanxi/lib/modules/home/moment_image_preview_page.dart`

**布局**
- 背景：纯黑 `Colors.black`
- 内容：`InteractiveViewer(minScale: 1.0, maxScale: 4.0)` 包裹图片
- 图片适配：`BoxFit.contain`，完整显示在屏幕内
- 状态栏：隐藏 `SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive)`

**交互**
- 点击任意位置 → `Navigator.pop` 关闭
- 双指捏合 → 缩放（1x~4x）
- 双指平移 → 移动图片（缩放 > 1x 时）

### 接入点

| 文件 | 位置 | 行为 |
|------|------|------|
| `moment_card.dart` | `MomentMediaGrid` 的 `onTap` | `Navigator.push` 到 `MomentImagePreviewPage` |
| `my_moments_page.dart` | 同上 | 复用同一个预览页（`MomentCard` 已统一处理） |

`MomentCard` 第 100 行原有 `// TODO: 点击打开媒体预览`，接入即完成该 TODO。

### 无需改动

- `MomentMediaGrid` 回调签名不变
- `MomentListView` 无需修改
- 视频点击行为不变（仅图片接入，视频扩展后续处理）
