# 视频通话对方画面黑屏问题分析报告

> 日期: 2026-04-20
> 问题: 在视频通话页面，对方的画面显示黑屏，没有视频内容。

---

## 视频架构概览

### 发送端（本地相机 → Agora → 对方）

```
Flutter BeautyCameraView (PlatformView)
  → MtSurfaceCameraView (Android GLSurfaceView + Renderer)
    → MtCamera.openCamera() / startPreview()
      → SurfaceTexture (OES Texture)
        → FBEffect.processTextureOES() 美颜处理
          → FBPreviewRenderer.render() 渲染到 GLSurfaceView (本地预览)
          → glReadPixels() 读取像素
            → invokeMethod("onFrame") → beauty_plugin channel
              → Flutter: _handleNativeMethod → engine.getMediaEngine().pushVideoFrame()
                → Agora 编码 → 发送到远端
```

### 接收端（对方相机 → Agora → 本地）

```
对方发送视频流
  → Agora 自动订阅 (autoSubscribeVideo: true)
    → Flutter: AgoraVideoView.remote() 渲染
      → RtcConnection(channelId) + uid + VideoCanvas
```

---

## 根因分析

### 关键发现

#### 1. 帧推送依赖 `shouldPushToAgora` 标志

**文件**: `huanxi/lib/packages/mt_plugin/android/src/main/kotlin/.../MtPlugin.kt:449`

```kotlin
var shouldPushToAgora: Boolean = false  // 默认 false
```

**文件**: `huanxi/lib/packages/mt_plugin/android/src/main/kotlin/.../MtSurfaceCameraView.kt:95`

```kotlin
if (MtPlugin.shouldPushToAgora) {  // 只有为 true 时才推流
    // glReadPixels + rgbaToBgra() + invokeMethod("onFrame")
}
```

只有当 Flutter 端调用 `_startNativePush()` → `beautyChannel.invokeMethod('startAgoraPush')` 后，Android 端的 `shouldPushToAgora` 才会被设为 `true`。

#### 2. `_startNativePush` 调用时机

**文件**: `huanxi/lib/modules/call/controllers/call_rtc_controller.dart:259-276`

```dart
void markJoined(int localUid) {
    if (!_joinedCallbackEmitted) {
        _joinedCallbackEmitted = true;
        onCallConnected();
        _startNativePush();  // 在 join 成功后通知原生开始推流
    }
}
```

潜在问题：如果 `BeautyCameraView` 对应的 `GLSurfaceView` 还未完成渲染（`onSurfaceChanged` 未触发 → 相机未打开），`shouldPushToAgora` 已经被设为 `true`，但此时 `isRenderInit = false`，美颜处理不工作。

#### 3. 相机预览延迟初始化

**文件**: `MtSurfaceCameraView.kt:68-78`

```kotlin
override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
    setupPreviewRenderer(width, height, setPreviewRotation = true)
    setupCameraPreview()  // ← 相机在这里才真正打开
}
```

相机预览不是在 Plugin 初始化时打开的，而是在 `BeautyCameraView` widget 创建并 attach 到窗口后，`GLSurfaceView.onSurfaceChanged` 被调用时才打开。

#### 4. `renderOESTexture` 方法名错误

**文件**: `huanxi/lib/packages/mt_plugin/mt_plugin.dart:21-24`

```dart
static Future<int?> renderOESTexture(int textId) async {
    return await _channel.invokeMethod(
        MTAction.SET_WATERMARK_NAME.methodName,  // ← 错误！应该是 RENDER_TEXTURE
        <String, dynamic>{"textureId": textId});
}
```

调用了错误的方法名称 `SET_WATERMARK_NAME`，而参数是 `textureId`，方法名与参数不匹配。

#### 5. 视频编码参数偏低

**文件**: `huanxi/lib/modules/call/controllers/call_rtc_controller.dart:397-406`

```dart
VideoEncoderConfiguration(
  dimensions: VideoDimensions(width: 640, height: 480),
  frameRate: 12,
  bitrate: 600,  // ⚠️ 600kbps 对于 480p 来说偏低
)
```

600kbps 在弱网环境下可能导致帧被严重压缩或丢弃。

---

## 可能根因（按概率排序）

### 根因 1：`shouldPushToAgora` 未正确触发，导致没有帧被推送
**验证**：查看 logcat 中是否有 `agora push frame sample luma=` 日志（每 30 帧输出一次）

### 根因 2：GLSurfaceView 渲染器未就绪就尝试推流
**验证**：查看 logcat 中是否有 `camera preview ready with size=` 日志

### 根因 3：对方侧使用相同架构但未正确推送（对方侧问题）
**验证**：需要确认对方是否也使用了 FaceBeauty 外部视频源架构

### 根因 4：`renderOESTexture` 调用了错误的方法名
**验证**：检查该方法是否被调用，以及 Android 端是否有对应的方法处理

### 根因 5：Agora 视频订阅未生效
**验证**：查看 logcat 中 `remote joined, uid=` 和 `AgoraVideoView` 相关日志

---

## 调试步骤

### 第一步：收集 Android logcat

```bash
adb logcat | grep -E "MtCameraVie|CALL_FLOW|beauty.method|onUserJoined|remote video"
```

需要确认的日志：
1. `MtCameraVie: camera preview ready with size=` → 相机是否成功打开
2. `MtCameraVie: agora push frame sample luma=X` → 是否有帧被推送（luma > 6 = 正常彩色画面；luma ≤ 6 = 黑帧）
3. `CALL_FLOW: remote joined, uid=` → 远端是否加入了频道
4. `CALL_FLOW: rtc state changed: joined=true, remoteUid=X` → 本端 join + 远端 uid 状态

### 第二步：判断是哪一端的问题

- **如果 `agora push frame sample luma=` 正常输出且 luma > 6**：本地推流正常，问题在对方或 Agora 传输
- **如果 `camera preview ready` 没有日志**：相机未打开，检查相机权限和 FBEffect 初始化
- **如果 `remote joined` 没有日志**：对方未加入频道，检查对方的 RTC 初始化

---

## 建议修复方案

### 修复 1：确保相机预览就绪后再开始推流

在 `call_rtc_controller.dart` 中，不应该在 join 成功后就立即调用 `_startNativePush()`，而应该等待 Android 端通知相机预览已就绪。

### 修复 2：提高视频码率

将 `bitrate: 600` 提高到 `800-1000`：
```dart
VideoEncoderConfiguration(
  dimensions: VideoDimensions(width: 640, height: 480),
  frameRate: 12,
  bitrate: 1000,  // 建议提高到 1000kbps
)
```

### 修复 3：修正 `renderOESTexture` 方法名

检查 Android 端是否存在对应的 `RENDER_TEXTURE` action 并修正调用。

### 修复 4：添加调试日志

在 `_startNativePush` 调用前后添加日志，确认 Android 端是否收到了 `startAgoraPush` 调用。
