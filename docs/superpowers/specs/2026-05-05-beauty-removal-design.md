# 美颜功能清理设计方案

**日期**: 2026-05-05
**目标**: 移除 FaceBeauty 美颜 SDK 及相关代码，确保视频通话功能不受影响
**方案**: A - 快速恢复 Agora 内置相机

---

## 背景

当前美颜功能使用 FaceBeauty SDK，与 Agora 深度耦合（外部视频源模式）。美颜到期且计划更换服务商，需清理现有代码。

---

## 一、Flutter 层清理

### 1.1 删除文件

| 路径 | 说明 |
|------|------|
| `huanxi/lib/modules/beauty/` | 整个目录（beauty_camera_view.dart, beauty_panel.dart, beauty_controller.dart, beauty_settings_page.dart） |
| `huanxi/lib/packages/mt_plugin/` | 整个包（含 mt_plugin.dart, Android/iOS 原生代码，资源文件） |
| `huanxi/test/modules/beauty/` | 3个测试文件 |
| `huanxi/mt_icon/icon_home_quick_beauty.png` | mt_plugin 的图标资源 |
| `backend/scripts/init_face_beauty_key.py` | 后端初始化脚本 |

### 1.2 修改文件

#### `app_router.dart`
- 删除 `beauty_settings_page.dart` import
- 删除 `beautySettings` 路由定义
- 删除 `beautySettings` 常量

#### `auth_provider.dart`
- `AppInitState` 删除 `faceBeautyKey` 字段
- 删除 `faceBeautyKeyProvider`

#### `app_constants.dart`
- 删除所有 `beauty*` 存储 key 常量（共 16 个）

#### `profile_page.dart`
- 删除"美颜设置"菜单项

#### `call_room_page.dart`
- 删除 `import '../beauty/beauty_camera_view.dart'` 和 `'../beauty/beauty_panel.dart'`
- 删除 `_isBeautyPanelVisible` 状态变量
- 删除 `_toggleBeautyPanel()`、`_closeBeautyPanel()` 方法
- 删除 `_buildInlineBeautyPanel()` 方法
- 删除通话底部工具栏的"美颜"按钮（`_ControlButton(icon: Icons.auto_awesome, label: '美颜', ...)`）
- 删除 `computeCallBeautySheetMinHeight`/`computeCallBeautySheetMaxHeight` 辅助函数

#### `call_rtc_controller.dart`
- 删除 `import 'package:mt_plugin/mt_plugin.dart'`
- 删除 `beautyChannel` MethodChannel 定义
- `initRtc()` 方法：
  - 删除 `faceBeautyKey` 参数
  - 删除 `MtPlugin.initSdk()` 调用
  - 删除 `beautyChannel.setMethodCallHandler` 设置
  - 删除 `setExternalVideoSource(enabled: true)`
  - **改用** `engine.startPreview()` 启用本地预览
- `leaveAndRelease()` 方法：
  - 删除 `_stopNativePush()` 调用
- 删除 `_startNativePush()`、`_stopNativePush()`、`_switchNativeCamera()` 方法
- 删除 `_handleNativeMethod()` 回调处理
- `toggleCamera()` 方法改用 `engine.muteLocalVideoStream()`
- `flipCamera()` 方法改用 `engine.switchCamera()`
- 删除 `previewReady` / `cameraSwitchResult` / `onFrame` 等原生回调处理逻辑
- 删除 RTC engine `useFlutterTexture: true`（改回默认）

#### `pubspec.yaml`
- 删除 `mt_plugin` 本地依赖：
  ```yaml
  # 删除
  mt_plugin:
    path: packages/mt_plugin
  ```

---

## 二、iOS 层清理

### 2.1 修改 `ios/Podfile`

删除 FaceBeauty 相关依赖：
```ruby
# 删除
pod 'Masonry', '~> 1.1'
pod 'ZipArchive', '~> 2.5'
```

### 2.2 删除文件

| 路径 | 说明 |
|------|------|
| `huanxi/ios/Podfile.lock` | 需重新 pod install |
| `huanxi/ios/Vendored/FaceBeauty.framework/` | FaceBeauty SDK |
| `huanxi/ios/Vendored/FaceBeauty.bundle/` | FaceBeauty 资源包 |

---

## 三、Android 层清理

### 3.1 删除 `huanxi/lib/packages/mt_plugin/android/` 整个目录

包含 Kotlin 源码、assets 资源（fbeffect/beauty/ 滤镜资源）。

### 3.2 删除 SDK 文件

| 路径 | 说明 |
|------|------|
| `huanxi/android/app/libs/FaceBeauty.aar` | FaceBeauty SDK |
| `huanxi/android/app/libs/_tmp_facebeauty/` | 临时配置目录 |

### 3.3 修改 `huanxi/android/app/proguard-rules.pro`

删除以下规则：
```proguard
# 删除
# mt_plugin - dontwarn missing classes
-dontwarn com.toivan.mtcamera.mt_plugin.**
-keep class com.toivan.mtcamera.mt_plugin.** { *; }

# FaceBeauty SDK
-keep class com.nimo.facebeauty.** { *; }
-dontwarn com.nimo.facebeauty.**
```

### 3.4 修改 `huanxi/android/app/build.gradle.kts`

从 `mt_plugin` 模块中删除 FaceBeauty 依赖：
```kotlin
// 删除
dependencies {
    compileOnly(files("${rootProject.projectDir}/app/libs/FaceBeauty.aar"))
}
```

---

## 四、后端层清理

### 4.1 修改 `backend/app/api/v1/app/bootstrap.py`

从 `/init/bootstrap` 返回数据中删除 `face_beauty` 字段：
```python
# 删除
"face_beauty": {
    "key": face_beauty_key,
},
```

### 4.2 管理后台（可选）

`backend/web/src/views/system/config/index.vue` 中的美颜配置 UI 保留或删除均可，不影响功能。

---

## 五、通话功能变更说明

### 变更前（外部视频源模式）
```
MtSurfaceCameraView (原生相机 + FaceBeauty)
    → GL 帧捕获 → BGRA 转换 → beautyChannel.onFrame
        → Flutter _handleNativeMethod()
            → engine.getMediaEngine().pushVideoFrame()
```

### 变更后（内置相机模式）
```
engine.startPreview()
    → Agora SDK 内置摄像头采集
    → 直接发布 publishCameraTrack: true
```

**本地预览**：改用标准 `AgoraVideoView`（`VideoSourceType.videoSourceCamera`）

**前后摄切换**：使用 `engine.switchCamera()` 或 `setCameraDevice` API

---

## 六、验证清单

清理完成后必须验证：

| 验证项 | 检查方式 |
|--------|----------|
| Flutter 分析通过 | `flutter analyze` 无错误 |
| 通话页面正常打开 | 启动 App，进入通话房间 |
| 本地预览正常显示 | 通话界面显示本地摄像头画面 |
| 前后摄切换正常 | 点击翻转按钮，摄像头切换 |
| 远程视频正常显示 | 对方画面正常显示 |
| 无残留 beauty import | 代码中搜索 `beauty`、`FaceBeauty`、`mt_plugin` 无结果 |

---

## 七、风险控制

1. **备份**：清理前确认 git 工作区干净，必要时可回滚
2. **分步执行**：按 Flutter → iOS → Android → 后端顺序清理
3. **即时验证**：每步清理后运行 `flutter analyze` 确保无语法错误