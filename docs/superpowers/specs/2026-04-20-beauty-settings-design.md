# 美颜设置入口设计

## 1. 概述

在"我的"页面添加"美颜设置"入口，用户可以预览和调整美颜参数。参数与通话房间中的美颜面板互通，无论在哪边设置，都自动持久化保存。

## 2. 架构

### 数据流

```
用户调整参数
    ↓
BeautyController 更新 state
    ├─ _syncToNative() → 实时同步到美颜SDK
    └─ saveToStorage() → 持久化到 shared_preferences

App启动 / 进入设置页面
    ↓
BeautyController.init()
    ├─ loadFromStorage() → 读取已保存参数
    └─ _syncToNative() → 同步到美颜SDK
```

### 共享策略

- 通话房间和设置页面共用同一个 `beautyControllerProvider`
- 保持现有 `autoDispose` 策略（页面退出时销毁），但 Controller 初始化时从 storage 加载配置
- 首次安装时使用默认值

## 3. 页面设计

### BeautySettingsPage

- **顶部区域 (60%)**：相机实时预览，`BeautyCameraView` 填满，黑色背景
- **底部区域 (40%)**：`BeautyPanel` 直接嵌入（复用现有组件）
- **导航栏**：返回按钮 + 标题"美颜设置"
- **无保存按钮**：所有调整实时生效 + 自动保存

### ProfilePage 入口

在"我的"页面菜单列表添加：
- 图标：`Icons.auto_awesome`
- 标题："美颜设置"
- 颜色：与 AppTheme.primaryColor 保持一致

## 4. 改动清单

| 文件 | 类型 | 说明 |
|------|------|------|
| `beauty_controller.dart` | 修改 | 添加 persistence（load/save via shared_preferences） |
| `beauty_settings_page.dart` | 新增 | 美颜设置独立页面 |
| `app_router.dart` | 修改 | 注册路由 `beautySettings` |
| `profile_page.dart` | 修改 | 添加"美颜设置"菜单项 |
| `app_constants.dart` | 修改 | 添加美颜存储 key 常量 |

## 5. 存储方案

存储 key 前缀 `beauty_`，避免与其他 storage key 冲突：

- `beauty_whitening` / `beauty_blurriness` / `beauty_rosiness` / `beauty_clearness` / `beauty_brightness`
- `beauty_eye_enlarging` / `beauty_eye_rounding` / `beauty_cheek_thinning` / `beauty_cheek_v` / `beauty_cheek_narrowing` / `beauty_chin` / `beauty_forehead` / `beauty_nose_thinning`
- `beauty_is_beauty_enabled` / `beauty_is_face_shape_enabled` / `beauty_is_render_enabled`
- `beauty_current_filter` / `beauty_filter_intensity`

## 6. 非功能需求

- 不支持相机切换（固定前置摄像头）
- BeautyPanel 直接嵌入页面底部，不使用 bottom sheet
- 无需额外保存按钮