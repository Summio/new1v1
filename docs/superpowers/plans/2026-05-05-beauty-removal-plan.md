# 美颜功能清理实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 移除 FaceBeauty 美颜 SDK 及所有相关代码，将视频通话从外部视频源模式恢复到 Agora 内置相机模式，确保视频通话功能完整可用。

**Architecture:** 将通话从 "MtSurfaceCameraView 原生相机采集 + FaceBeauty 处理 + beautyChannel 推送帧" 架构，改为 "Agora 内置 startPreview() 相机采集" 标准架构。本地预览改用标准 AgoraVideoView，删除 mt_plugin 包及其所有原生依赖。

**Tech Stack:** Flutter / Agora RTC Engine / iOS / Android

---

## 文件变更总览

| 操作 | 路径 |
|------|------|
| 删除 | `huanxi/lib/modules/beauty/` (整个目录) |
| 删除 | `huanxi/lib/packages/mt_plugin/` (整个包) |
| 删除 | `huanxi/test/modules/beauty/` (整个目录) |
| 删除 | `huanxi/test/modules/call/call_room_page_beauty_sheet_test.dart` |
| 删除 | `huanxi/mt_icon/icon_home_quick_beauty.png` |
| 删除 | `huanxi/android/app/libs/FaceBeauty.aar` |
| 删除 | `huanxi/android/app/libs/_tmp_facebeauty/` |
| 删除 | `backend/scripts/init_face_beauty_key.py` |
| 修改 | `huanxi/pubspec.yaml` |
| 修改 | `huanxi/lib/app/routes/app_router.dart` |
| 修改 | `huanxi/lib/app/providers/auth_provider.dart` |
| 修改 | `huanxi/lib/core/constants/app_constants.dart` |
| 修改 | `huanxi/lib/modules/home/profile_page.dart` |
| 修改 | `huanxi/lib/modules/call/call_room_page.dart` |
| 修改 | `huanxi/lib/modules/call/controllers/call_rtc_controller.dart` |
| 修改 | `huanxi/android/app/proguard-rules.pro` |
| 修改 | `huanxi/ios/Podfile` |
| 修改 | `backend/app/api/v1/app/bootstrap.py` |

---

## Task 1: 删除 Flutter beauty 模块和 mt_plugin 包

**Files:**
- 删除: `huanxi/lib/modules/beauty/beauty_camera_view.dart`
- 删除: `huanxi/lib/modules/beauty/beauty_panel.dart`
- 删除: `huanxi/lib/modules/beauty/beauty_controller.dart`
- 删除: `huanxi/lib/modules/beauty/beauty_settings_page.dart`
- 删除: `huanxi/lib/modules/beauty/` (整个目录)
- 删除: `huanxi/lib/packages/mt_plugin/` (整个目录)
- 删除: `huanxi/test/modules/beauty/beauty_controller_channel_test.dart`
- 删除: `huanxi/test/modules/beauty/beauty_panel_layout_test.dart`
- 删除: `huanxi/test/modules/beauty/` (整个目录)
- 删除: `huanxi/test/modules/call/call_room_page_beauty_sheet_test.dart`
- 删除: `huanxi/mt_icon/icon_home_quick_beauty.png`

- [ ] **Step 1: 验证 beauty 模块文件存在**

```bash
ls huanxi/lib/modules/beauty/
ls huanxi/lib/packages/mt_plugin/
ls huanxi/test/modules/beauty/
ls huanxi/mt_icon/icon_home_quick_beauty.png
```
Expected: 文件列表输出

- [ ] **Step 2: 删除 beauty 模块目录**

```bash
rm -rf huanxi/lib/modules/beauty/
```
Expected: 目录已删除

- [ ] **Step 3: 删除 mt_plugin 包目录**

```bash
rm -rf huanxi/lib/packages/mt_plugin/
```
Expected: 目录已删除

- [ ] **Step 4: 删除 beauty 测试文件**

```bash
rm -rf huanxi/test/modules/beauty/
rm -f huanxi/test/modules/call/call_room_page_beauty_sheet_test.dart
```
Expected: 文件已删除

- [ ] **Step 5: 删除 mt_plugin 图标**

```bash
rm -f huanxi/mt_icon/icon_home_quick_beauty.png
```
Expected: 文件已删除

- [ ] **Step 6: 提交**

```bash
git add -A
git commit -m "chore: 删除美颜模块和 mt_plugin 包"
```
---

## Task 2: 修改 pubspec.yaml 移除 mt_plugin 依赖

**Files:**
- 修改: `huanxi/pubspec.yaml`

- [ ] **Step 1: 读取当前 pubspec.yaml 确认 mt_plugin 位置**

- [ ] **Step 2: 删除 mt_plugin 依赖块**

在 `pubspec.yaml` 中删除以下内容：

```yaml
  camera: ^0.11.2+1          # 保留，camera 包还有其他用途
  image_picker: ^1.1.2         # 保留
  flutter_image_compress: ^2.4.0
  video_compress: ^3.1.4
  mt_plugin:                   # 删除此块
    path: lib/packages/mt_plugin
```

改为：

```yaml
  camera: ^0.11.2+1
  image_picker: ^1.1.2
  flutter_image_compress: ^2.4.0
  video_compress: ^3.1.4
```

- [ ] **Step 3: 验证 flutter pub get 成功**

```bash
cd huanxi && flutter pub get
```
Expected: 无错误输出，pubspec.lock 更新

- [ ] **Step 4: 提交**

```bash
git add huanxi/pubspec.yaml
git commit -m "chore: 从 pubspec.yaml 移除 mt_plugin 依赖"
```
---

## Task 3: 修改 app_router.dart 移除 beauty 路由

**Files:**
- 修改: `huanxi/lib/app/routes/app_router.dart`

- [ ] **Step 1: 删除 import**

```dart
// 删除这行
import '../../modules/beauty/beauty_settings_page.dart';
```

- [ ] **Step 2: 删除路由常量**

```dart
// 删除这行
static const String beautySettings = '/profile/beauty';
```

- [ ] **Step 3: 删除路由配置**

删除以下 GoRoute 定义：

```dart
GoRoute(
  path: AppRoutes.beautySettings,
  builder: (context, state) => const BeautySettingsPage(),
),
```

- [ ] **Step 4: 验证 flutter analyze 无 beauty 相关错误**

```bash
cd huanxi && flutter analyze lib/app/routes/app_router.dart
```
Expected: 无错误

- [ ] **Step 5: 提交**

```bash
git add huanxi/lib/app/routes/app_router.dart
git commit -m "chore: 移除美颜设置页面路由"
```
---

## Task 4: 修改 auth_provider.dart 移除 faceBeautyKey

**Files:**
- 修改: `huanxi/lib/app/providers/auth_provider.dart`

- [ ] **Step 1: 删除 AppInitState 中的 faceBeautyKey 字段**

找到 `AppInitState` 类定义：

```dart
class AppInitState {
  final bool isLoading;
  final bool loaded;
  final String coinName;
  final String diamondName;
  final int? imSdkAppId;
  final bool imConfigured;
  final String? faceBeautyKey;  // 删除此字段及下一行的空值

  const AppInitState({
    this.isLoading = false,
    this.loaded = false,
    this.coinName = '金币',
    this.diamondName = '钻石',
    this.imSdkAppId,
    this.imConfigured = false,
    this.faceBeautyKey,  // 删除
  });
```

改为：

```dart
class AppInitState {
  final bool isLoading;
  final bool loaded;
  final String coinName;
  final String diamondName;
  final int? imSdkAppId;
  final bool imConfigured;

  const AppInitState({
    this.isLoading = false,
    this.loaded = false,
    this.coinName = '金币',
    this.diamondName = '钻石',
    this.imSdkAppId,
    this.imConfigured = false,
  });
```

- [ ] **Step 2: 删除 copyWith 方法中的 faceBeautyKey**

找到 `copyWith` 方法中的这行：

```dart
    Object? faceBeautyKey = const _NoValue(),  // 删除
```

删除该行。同时修改 return 语句，删除相关字段。

- [ ] **Step 3: 删除 AppInitNotifier.init() 中的 faceBeautyKey 赋值**

找到：

```dart
final faceBeautyKey = respData['face_beauty']?['key'] as String?;
```

和：

```dart
state = state.copyWith(
  ...
  faceBeautyKey: faceBeautyKey,  // 删除此行
);
```

- [ ] **Step 4: 删除 faceBeautyKeyProvider**

删除以下内容：

```dart
/// FaceBeauty SDK Key Provider
final faceBeautyKeyProvider = Provider<String?>((ref) {
  return ref.watch(appInitProvider).faceBeautyKey;
});
```

- [ ] **Step 5: 验证 flutter analyze**

```bash
cd huanxi && flutter analyze lib/app/providers/auth_provider.dart
```
Expected: 无错误

- [ ] **Step 6: 提交**

```bash
git add huanxi/lib/app/providers/auth_provider.dart
git commit -m "chore: 移除 faceBeautyKey 字段和 Provider"
```
---

## Task 5: 修改 app_constants.dart 移除 beauty 存储 key 常量

**Files:**
- 修改: `huanxi/lib/core/constants/app_constants.dart`

- [ ] **Step 1: 删除美颜存储 key 常量**

在 `AppConstants` 类中删除以下常量（共 16 个）：

```dart
/// 美颜参数存储 Keys
static const String beautyWhitening = 'beauty_whitening';
static const String beautyBlurriness = 'beauty_blurriness';
static const String beautyRosiness = 'beauty_rosiness';
static const String beautyClearness = 'beauty_clearness';
static const String beautyBrightness = 'beauty_brightness';
static const String beautyEyeEnlarging = 'beauty_eye_enlarging';
static const String beautyEyeRounding = 'beauty_eye_rounding';
static const String beautyCheekThinning = 'beauty_cheek_thinning';
static const String beautyCheekV = 'beauty_cheek_v';
static const String beautyCheekNarrowing = 'beauty_cheek_narrowing';
static const String beautyChin = 'beauty_chin';
static const String beautyForehead = 'beauty_forehead';
static const String beautyNoseThinning = 'beauty_nose_thinning';
static const String beautyIsBeautyEnabled = 'beauty_is_beauty_enabled';
static const String beautyIsFaceShapeEnabled = 'beauty_is_face_shape_enabled';
static const String beautyIsRenderEnabled = 'beauty_is_render_enabled';
static const String beautyCurrentFilter = 'beauty_current_filter';
static const String beautyFilterIntensity = 'beauty_filter_intensity';
```

- [ ] **Step 2: 验证 flutter analyze**

```bash
cd huanxi && flutter analyze lib/core/constants/app_constants.dart
```
Expected: 无错误

- [ ] **Step 3: 提交**

```bash
git add huanxi/lib/core/constants/app_constants.dart
git commit -m "chore: 移除美颜存储 key 常量"
```
---

## Task 6: 修改 profile_page.dart 移除美颜设置入口

**Files:**
- 修改: `huanxi/lib/modules/home/profile_page.dart`

- [ ] **Step 1: 删除美颜设置菜单项**

找到以下行并删除：

```dart
_buildMenuTile(icon: Icons.auto_awesome, title: '美颜设置', iconColor: const Color(0xFFFF6B9D), onTap: () => context.push(AppRoutes.beautySettings)),
```

- [ ] **Step 2: 验证 flutter analyze**

```bash
cd huanxi && flutter analyze lib/modules/home/profile_page.dart
```
Expected: 无错误

- [ ] **Step 3: 提交**

```bash
git add huanxi/lib/modules/home/profile_page.dart
git commit -m "chore: 移除个人页面中美颜设置入口"
```
---

## Task 7: 重写 call_rtc_controller.dart 恢复 Agora 内置相机

**Files:**
- 修改: `huanxi/lib/modules/call/controllers/call_rtc_controller.dart`

这是最关键的文件改动。需要将外部视频源模式改回 Agora 内置相机模式。

- [ ] **Step 1: 删除 import**

删除以下行：

```dart
import 'package:mt_plugin/mt_plugin.dart';
```

- [ ] **Step 2: 删除 beautyChannel**

删除 `CallRtcController` 类中的以下内容：

```dart
// MethodChannel 用于与原生 FaceBeauty 通信
static const MethodChannel _beautyChannel = MethodChannel('beauty_plugin');
```

- [ ] **Step 3: 删除 initRtc() 中的 FaceBeauty 初始化和 beautyChannel 设置**

在 `initRtc()` 方法中删除：

```dart
// 初始化 FaceBeauty SDK
if (faceBeautyKey != null && faceBeautyKey.isNotEmpty) {
  final beautyInitAt = DateTime.now();
  try {
    MtPlugin.initSdk(faceBeautyKey);
    onLog?.call(
      'faceBeauty init done in ${DateTime.now().difference(beautyInitAt).inMilliseconds}ms',
    );
  } catch (e) {
    onLog?.call('FaceBeauty SDK init failed: $e');
  }
} else {
  onLog?.call('faceBeauty key missing, skip sdk init');
}
```

删除 `faceBeautyKey` 参数：

```dart
Future<void> initRtc({
  required void Function() onCallConnected,
  required void Function(String endReason) onRemoteEnd,
  void Function(String message)? onLog,
  String? faceBeautyKey,  // 删除此参数
}) async {
```

删除：

```dart
// 设置原生回调
_beautyChannel.setMethodCallHandler(_handleNativeMethod);
```

- [ ] **Step 4: 删除 setExternalVideoSource，改用 startPreview**

找到：

```dart
// 启用外部视频源模式（FaceBeauty 原生相机采集 + 美颜处理）
await engine.getMediaEngine().setExternalVideoSource(
  enabled: true,
  useTexture: false,
);
onLog?.call('external video source enabled');
```

替换为：

```dart
// 启用 Agora 内置视频预览
await engine.startPreview();
onLog?.call('startPreview done');
```

- [ ] **Step 5: 修改 joinChannel 的 options**

找到 `ChannelMediaOptions` 配置：

```dart
options: const ChannelMediaOptions(
  channelProfile: ChannelProfileType.channelProfileCommunication,
  clientRoleType: ClientRoleType.clientRoleBroadcaster,
  // 外部视频源模式下，不发布内置摄像头轨道
  publishCameraTrack: false,
  // 外部源帧通过 pushVideoFrame(trackId=0) 推送，需要发布自定义视频轨。
  publishCustomVideoTrack: true,
  customVideoTrackId: 0,
  publishMicrophoneTrack: true,
  autoSubscribeAudio: true,
  autoSubscribeVideo: true,
),
```

改为：

```dart
options: const ChannelMediaOptions(
  channelProfile: ChannelProfileType.channelProfileCommunication,
  clientRoleType: ClientRoleType.clientRoleBroadcaster,
  publishCameraTrack: true,
  publishCustomVideoTrack: false,
  customVideoTrackId: 0,
  publishMicrophoneTrack: true,
  autoSubscribeAudio: true,
  autoSubscribeVideo: true,
),
```

- [ ] **Step 6: 删除所有原生回调处理和外部帧处理逻辑**

删除整个 `_handleNativeMethod` 方法（从 `Future<dynamic> _handleNativeMethod` 到方法结束的所有内容）。

删除 `_startNativePush`、`_stopNativePush`、`_switchNativeCamera` 三个方法。

- [ ] **Step 7: 修改 toggleCamera() 使用 Agora 内置 API**

找到 `toggleCamera()` 方法，替换为：

```dart
Future<void> toggleCamera() async {
  final next = !state.isCameraOn;
  try {
    await _engine?.muteLocalVideoStream(!next);
  } catch (e) {
    onLog?.call('toggleCamera failed: $e');
  }
  if (!mounted) {
    return;
  }
  state = state.copyWith(isCameraOn: next);
}
```

- [ ] **Step 8: 修改 flipCamera() 使用 Agora 内置 API**

找到 `flipCamera()` 方法，替换为：

```dart
Future<void> flipCamera() async {
  _flowLog('ui.flipCamera.start');
  state = state.copyWith(isFlipping: true);
  try {
    await _engine?.switchCamera();
    if (!mounted) {
      return;
    }
    // 前后摄切换后 Agora 会更新镜像状态，这里直接翻转 isFrontCamera 状态
    final nextIsFront = !state.isFrontCamera;
    state = state.copyWith(isFlipping: false, isFrontCamera: nextIsFront);
    _flowLog('ui.flipCamera.done', extra: {'next': nextIsFront ? 'front' : 'back'});
  } catch (e) {
    _flowLog('ui.flipCamera.error', extra: {'error': e.toString()});
    if (mounted) {
      state = state.copyWith(isFlipping: false);
    }
  }
}
```

- [ ] **Step 9: 修改 leaveAndRelease() 删除原生推流停止**

找到 `leaveAndRelease()` 方法，删除以下行：

```dart
// 离开前先停止原生推流
_stopNativePush();
```

- [ ] **Step 10: 删除 dispose() 中的 beautyChannel 清理**

找到 `dispose()` 方法，删除：

```dart
_beautyChannel.setMethodCallHandler(null);
```

- [ ] **Step 11: 删除类级别的外部帧相关状态变量**

删除 `CallRtcController` 类中不再需要的成员变量：

- `_externalFrameLogCounter`
- `_externalFrameHeadLogCounter`
- `_externalBlackFrameCounter`
- `_externalFrameWarnCounter`
- `_externalPushOkCounter`
- `_externalFrameRotation`
- `_dropFramesDuringCameraSwitch`
- `_cameraSwitchDropGuardTimer`
- `_flipUiGuardTimer`
- `_cameraSwitchResumePushTimer`
- `_nativePushStarted`

- [ ] **Step 12: 删除 _flowLog 中的 rotation 相关逻辑**

简化 `_flowLog` 方法的 extra map，删除与 rotation、frame 相关的字段。

- [ ] **Step 13: 验证 flutter analyze**

```bash
cd huanxi && flutter analyze lib/modules/call/controllers/call_rtc_controller.dart
```
Expected: 无错误。可能有关于未使用变量的警告，逐个修复。

- [ ] **Step 14: 提交**

```bash
git add huanxi/lib/modules/call/controllers/call_rtc_controller.dart
git commit -m "feat: 重构通话 RTC 控制器，使用 Agora 内置相机替代外部视频源"
```
---

## Task 8: 修改 call_room_page.dart 移除美颜 UI 和 BeautyCameraView

**Files:**
- 修改: `huanxi/lib/modules/call/call_room_page.dart`

- [ ] **Step 1: 删除 beauty 相关 import**

删除：

```dart
import '../beauty/beauty_camera_view.dart';
import '../beauty/beauty_panel.dart';
```

- [ ] **Step 2: 删除 _isBeautyPanelVisible 状态变量和所有相关逻辑**

删除类成员变量：

```dart
bool _isBeautyPanelVisible = false;
double _beautyPanelHeightFactor = _beautyPanelInitialFactor;
```

删除 `_toggleBeautyPanel()` 方法。

删除 `_closeBeautyPanel()` 方法。

- [ ] **Step 3: 删除 initRtc() 中 faceBeautyKey 的传入**

找到：

```dart
faceBeautyKey: ref.read(faceBeautyKeyProvider),
```

删除此参数（因为 `initRtc` 已不再需要该参数，见 Task 7）。

- [ ] **Step 4: 删除本地预览中的 BeautyCameraView**

找到：

```dart
if (rtcState.isCameraOn)
  const Positioned.fill(
    child: IgnorePointer(
      child: Opacity(opacity: 0.01, child: BeautyCameraView()),
    ),
  ),
```

删除整个这段代码。

- [ ] **Step 5: 删除美颜面板按钮**

找到并删除：

```dart
_ControlButton(
  icon: Icons.auto_awesome,
  label: '美颜',
  isActive: _isBeautyPanelVisible,
  onTap: _toggleBeautyPanel,
),
```

- [ ] **Step 6: 删除 _buildInlineBeautyPanel 方法**

删除整个 `_buildInlineBeautyPanel()` 方法定义（约 50 行）。

- [ ] **Step 7: 删除辅助函数**

删除 `computeCallBeautySheetMaxHeight` 和 `computeCallBeautySheetMinHeight` 函数。

- [ ] **Step 8: 删除相关的 _isRemoteInMainView 逻辑（如果仅为显示美颜面板存在）**

如果 `_isRemoteInMainView` 仅用于美颜面板时切换主视角，删除相关条件分支。**注意**：此变量可能也用于通话中的小窗口预览，需保留小窗口预览逻辑，仅删除美颜相关部分。

- [ ] **Step 9: 验证 flutter analyze**

```bash
cd huanxi && flutter analyze lib/modules/call/call_room_page.dart
```
Expected: 无错误

- [ ] **Step 10: 提交**

```bash
git add huanxi/lib/modules/call/call_room_page.dart
git commit -m "chore: 移除通话页面中美颜面板 UI 和相关逻辑"
```
---

## Task 9: 删除 Android FaceBeauty SDK 和 proguard 规则

**Files:**
- 删除: `huanxi/android/app/libs/FaceBeauty.aar`
- 删除: `huanxi/android/app/libs/_tmp_facebeauty/`
- 修改: `huanxi/android/app/proguard-rules.pro`

- [ ] **Step 1: 删除 FaceBeauty.aar**

```bash
rm -f huanxi/android/app/libs/FaceBeauty.aar
rm -rf huanxi/android/app/libs/_tmp_facebeauty/
```
Expected: 文件已删除

- [ ] **Step 2: 修改 proguard-rules.pro 删除 FaceBeauty/mt_plugin 规则**

找到并删除以下内容：

```proguard
# mt_plugin - dontwarn missing classes
-dontwarn com.toivan.mtcamera.mt_plugin.**
-keep class com.toivan.mtcamera.mt_plugin.** { *; }

# FaceBeauty SDK
-keep class com.nimo.facebeauty.** { *; }
-dontwarn com.nimo.facebeauty.**
```

- [ ] **Step 3: 验证 proguard-rules.pro 修改正确**

```bash
grep -n "facebeauty\|mt_plugin" huanxi/android/app/proguard-rules.pro
```
Expected: 无结果

- [ ] **Step 4: 提交**

```bash
git add -A huanxi/android/app/
git commit -m "chore: 删除 Android FaceBeauty SDK 和相关 proguard 规则"
```
---

## Task 10: 清理 iOS Podfile 和 mt_plugin.podspec 引用

**Files:**
- 修改: `huanxi/ios/Podfile`

- [ ] **Step 1: 修改 Podfile 删除 Masonry 和 ZipArchive**

找到并删除：

```ruby
# CocoaPods dependencies for FaceBeauty mt_plugin
pod 'Masonry', '~> 1.1'
pod 'ZipArchive', '~> 2.5'
```

- [ ] **Step 2: 运行 pod install 验证**

```bash
cd huanxi/ios && pod install
```
Expected: 无错误

- [ ] **Step 3: 提交**

```bash
git add huanxi/ios/Podfile
git commit -m "chore: 从 iOS Podfile 移除 FaceBeauty 相关依赖"
```
---

## Task 11: 删除后端 face_beauty 相关代码

**Files:**
- 删除: `backend/scripts/init_face_beauty_key.py`
- 修改: `backend/app/api/v1/app/bootstrap.py`

- [ ] **Step 1: 删除初始化脚本**

```bash
rm -f backend/scripts/init_face_beauty_key.py
```
Expected: 文件已删除

- [ ] **Step 2: 修改 bootstrap.py 移除 face_beauty 返回**

在 `bootstrap.py` 的 `get_app_bootstrap()` 函数中：

删除变量读取：

```python
face_beauty_key = (config_map.get("face_beauty_key") or "").strip()
```

删除返回数据中的字段：

```python
"face_beauty": {
    "key": face_beauty_key,
},
```

- [ ] **Step 3: 验证后端改动**

```bash
cd backend && python -c "from app.api.v1.app.bootstrap import router; print('ok')"
```
Expected: 输出 "ok"

- [ ] **Step 4: 提交**

```bash
git add -A backend/
git commit -m "chore: 移除后端 face_beauty 相关代码"
```
---

## Task 12: 全量验证

- [ ] **Step 1: Flutter 全量分析**

```bash
cd huanxi && flutter analyze
```
Expected: 无错误

- [ ] **Step 2: 搜索确认无 beauty 残留**

```bash
cd huanxi && grep -r "beauty\|BeautyCamera\|mt_plugin" lib/ --include="*.dart" -l 2>/dev/null | grep -v ".dart_tool"
```
Expected: 无结果（或仅有一些无关的变量名）

- [ ] **Step 3: 验证 pubspec.yaml 无 mt_plugin**

```bash
cd huanxi && grep "mt_plugin" pubspec.yaml
```
Expected: 无结果

- [ ] **Step 4: 全量提交**

```bash
git status
git add -A
git commit -m "feat: 完成美颜功能清理，回归 Agora 内置相机模式"
```

---

## 风险控制

1. **通话核心链路改动最大**（Task 7），建议完成后单独运行 `flutter analyze` 验证
2. **iOS Podfile** 变更需要 `pod install`，确保 CocoaPods 环境正常
3. 如遇 Agora `startPreview` 相关问题，检查 `agora_rtc_engine` 版本是否支持该 API
4. 前后摄切换使用 `engine.switchCamera()` 是 Agora 标准 API，向后兼容