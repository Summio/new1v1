# 美颜设置入口实现计划

**Goal:** 在"我的"页面添加"美颜设置"入口，用户可在独立页面预览相机并调整美颜参数，参数全局持久化共享。

**Architecture:** 美颜参数存储在 shared_preferences，BeautyController 初始化时加载、每次变更时保存。设置页面和通话房间共用同一个 `beautyControllerProvider`，通过 autoDispose 方式各自创建实例但共享持久化数据。

**Tech Stack:** Flutter + Riverpod + shared_preferences + BeautyCameraView (PlatformView) + MtPlugin

---

## 文件变更总览

| 文件 | 类型 | 说明 |
|------|------|------|
| `huanxi/lib/core/constants/app_constants.dart` | 修改 | 添加美颜存储 key 常量 |
| `huanxi/lib/modules/beauty/beauty_controller.dart` | 修改 | 添加 persistence (load/save via shared_preferences) |
| `huanxi/lib/modules/beauty/beauty_settings_page.dart` | 新增 | 美颜设置独立页面 |
| `huanxi/lib/app/routes/app_router.dart` | 修改 | 注册路由 `beautySettings` |
| `huanxi/lib/modules/home/profile_page.dart` | 修改 | 添加"美颜设置"菜单项 |

---

## Task 1: 添加美颜存储 key 常量

**Files:**
- Modify: `huanxi/lib/core/constants/app_constants.dart`

- [ ] **Step 1: 在 app_constants.dart 添加美颜存储 key 常量**

在 `storageFirstLaunch` 后添加：

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

- [ ] **Step 2: 验证修改正确**

Run: `grep -n "beautyWhitening\|beautyBlurriness" huanxi/lib/core/constants/app_constants.dart`
Expected: 能看到新增的常量定义

- [ ] **Step 3: Commit**

```bash
git add huanxi/lib/core/constants/app_constants.dart
git commit -m "feat: 添加美颜参数存储 key 常量"
```

---

## Task 2: 给 BeautyController 添加持久化

**Files:**
- Modify: `huanxi/lib/modules/beauty/beauty_controller.dart`

- [ ] **Step 1: 在 BeautyController 中添加 SharedPreferences 初始化和 load/save 方法**

在 `BeautyController` 类的 `onLog` 字段后、`super.initState()` 前添加：

```dart
SharedPreferences? _prefs;

Future<void> _loadFromStorage() async {
  _prefs ??= await SharedPreferences.getInstance();
  final prefs = _prefs!;
  _log('loading beauty params from storage');

  final hasData = prefs.containsKey(AppConstants.beautyWhitening);
  if (!hasData) {
    _log('no saved beauty data, using defaults');
    return;
  }

  state = state.copyWith(
    whitening: prefs.getInt(AppConstants.beautyWhitening) ?? 50,
    blurriness: prefs.getInt(AppConstants.beautyBlurriness) ?? 50,
    rosiness: prefs.getInt(AppConstants.beautyRosiness) ?? 20,
    clearness: prefs.getInt(AppConstants.beautyClearness) ?? 10,
    brightness: prefs.getInt(AppConstants.beautyBrightness) ?? 0,
    eyeEnlarging: prefs.getInt(AppConstants.beautyEyeEnlarging) ?? 0,
    eyeRounding: prefs.getInt(AppConstants.beautyEyeRounding) ?? 0,
    cheekThinning: prefs.getInt(AppConstants.beautyCheekThinning) ?? 0,
    cheekV: prefs.getInt(AppConstants.beautyCheekV) ?? 0,
    cheekNarrowing: prefs.getInt(AppConstants.beautyCheekNarrowing) ?? 0,
    chin: prefs.getInt(AppConstants.beautyChin) ?? 0,
    forehead: prefs.getInt(AppConstants.beautyForehead) ?? 0,
    noseThinning: prefs.getInt(AppConstants.beautyNoseThinning) ?? 0,
    isBeautyEnabled: prefs.getBool(AppConstants.beautyIsBeautyEnabled) ?? true,
    isFaceShapeEnabled: prefs.getBool(AppConstants.beautyIsFaceShapeEnabled) ?? false,
    isRenderEnabled: prefs.getBool(AppConstants.beautyIsRenderEnabled) ?? true,
    currentFilter: prefs.getString(AppConstants.beautyCurrentFilter),
    filterIntensity: prefs.getInt(AppConstants.beautyFilterIntensity) ?? 60,
  );
}

Future<void> _saveToStorage() async {
  _prefs ??= await SharedPreferences.getInstance();
  final prefs = _prefs!;
  await Future.wait([
    prefs.setInt(AppConstants.beautyWhitening, state.whitening),
    prefs.setInt(AppConstants.beautyBlurriness, state.blurriness),
    prefs.setInt(AppConstants.beautyRosiness, state.rosiness),
    prefs.setInt(AppConstants.beautyClearness, state.clearness),
    prefs.setInt(AppConstants.beautyBrightness, state.brightness),
    prefs.setInt(AppConstants.beautyEyeEnlarging, state.eyeEnlarging),
    prefs.setInt(AppConstants.beautyEyeRounding, state.eyeRounding),
    prefs.setInt(AppConstants.beautyCheekThinning, state.cheekThinning),
    prefs.setInt(AppConstants.beautyCheekV, state.cheekV),
    prefs.setInt(AppConstants.beautyCheekNarrowing, state.cheekNarrowing),
    prefs.setInt(AppConstants.beautyChin, state.chin),
    prefs.setInt(AppConstants.beautyForehead, state.forehead),
    prefs.setInt(AppConstants.beautyNoseThinning, state.noseThinning),
    prefs.setBool(AppConstants.beautyIsBeautyEnabled, state.isBeautyEnabled),
    prefs.setBool(AppConstants.beautyIsFaceShapeEnabled, state.isFaceShapeEnabled),
    prefs.setBool(AppConstants.beautyIsRenderEnabled, state.isRenderEnabled),
    if (state.currentFilter != null)
      prefs.setString(AppConstants.beautyCurrentFilter, state.currentFilter!),
    prefs.setInt(AppConstants.beautyFilterIntensity, state.filterIntensity),
  ]);
}
```

- [ ] **Step 2: 在构造函数中调用异步 load**

将构造函数改为同步，在 `_syncToNative()` 调用前先同步 load（用默认值），然后在 init 后异步覆盖：

```dart
BeautyController({this.onLog}) : super(const BeautyState()) {
  _log('BeautyController init');
  _syncToNative();
  // 异步加载已保存的参数，覆盖默认值并同步到 SDK
  Future.microtask(() async {
    await _loadFromStorage();
    _syncToNative();
  });
}
```

- [ ] **Step 3: 在 `_update` 方法中调用 save**

修改 `_update` 方法，在 `_syncToNative()` 后添加 `_saveToStorage()`：

```dart
void _update(BeautyState Function(BeautyState) updater) {
  state = updater(state);
  _syncToNative();
  _saveToStorage();
}
```

- [ ] **Step 4: 验证修改正确**

Run: `flutter analyze huanxi/lib/modules/beauty/beauty_controller.dart`
Expected: 无错误

- [ ] **Step 5: Commit**

```bash
git add huanxi/lib/modules/beauty/beauty_controller.dart
git commit -m "feat(beauty): 美颜参数持久化到 shared_preferences"
```

---

## Task 3: 创建美颜设置页面

**Files:**
- Create: `huanxi/lib/modules/beauty/beauty_settings_page.dart`

- [ ] **Step 1: 创建 beauty_settings_page.dart**

创建文件，内容如下：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import 'beauty_camera_view.dart';
import 'beauty_panel.dart';

class BeautySettingsPage extends ConsumerWidget {
  const BeautySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // 顶部导航栏
          SafeArea(
            bottom: false,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      '美颜设置',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48), // 占位，保持标题居中
                ],
              ),
            ),
          ),
          // 相机预览区域 (flex: 6)
          Expanded(
            flex: 6,
            child: Container(
              color: Colors.black,
              child: const Center(
                child: BeautyCameraView(),
              ),
            ),
          ),
          // 美颜面板区域 (flex: 4)
          Expanded(
            flex: 4,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: const BeautyPanel(),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 验证语法正确**

Run: `flutter analyze huanxi/lib/modules/beauty/beauty_settings_page.dart`
Expected: 无错误

- [ ] **Step 3: Commit**

```bash
git add huanxi/lib/modules/beauty/beauty_settings_page.dart
git commit -m "feat(beauty): 添加美颜设置页面 BeautySettingsPage"
```

---

## Task 4: 注册路由

**Files:**
- Modify: `huanxi/lib/app/routes/app_router.dart`

- [ ] **Step 1: 添加路由路径常量**

在 `AppRoutes` 类中，在 `recharge` 路由常量后添加：

```dart
static const String beautySettings = '/profile/beauty';
```

- [ ] **Step 2: 添加 import**

在文件顶部的 import 区域添加：

```dart
import '../../modules/beauty/beauty_settings_page.dart';
```

- [ ] **Step 3: 添加路由配置**

在 `AppRoutes.recharge` 路由定义后添加：

```dart
GoRoute(
  path: AppRoutes.beautySettings,
  builder: (context, state) => const BeautySettingsPage(),
),
```

- [ ] **Step 4: 验证修改正确**

Run: `flutter analyze huanxi/lib/app/routes/app_router.dart`
Expected: 无错误

- [ ] **Step 5: Commit**

```bash
git add huanxi/lib/app/routes/app_router.dart
git commit -m "feat: 注册美颜设置页面路由"
```

---

## Task 5: 在"我的"页面添加入口

**Files:**
- Modify: `huanxi/lib/modules/home/profile_page.dart`

- [ ] **Step 1: 添加 import**

在文件顶部的 import 区域添加：

```dart
import '../../app/routes/app_router.dart';
```

- [ ] **Step 2: 在菜单列表中添加"美颜设置"项**

在 `_buildMenuTile` 调用列表中找一个合适的位置添加（建议在"安全中心"之前）：

```dart
_buildMenuTile(icon: Icons.auto_awesome, title: '美颜设置', iconColor: const Color(0xFFFF6B9D), onTap: () => context.push(AppRoutes.beautySettings)),
```

- [ ] **Step 3: 验证修改正确**

Run: `flutter analyze huanxi/lib/modules/home/profile_page.dart`
Expected: 无错误

- [ ] **Step 4: Commit**

```bash
git add huanxi/lib/modules/home/profile_page.dart
git commit -m "feat(profile): 添加美颜设置入口"
```

---

## 验证清单

全部完成后，运行以下检查：

- [ ] `flutter analyze huanxi/` 无错误
- [ ] Git status 确认只有上述 5 个文件被修改
- [ ] 重新构建 APK 并在"我的"页面能看到"美颜设置"入口
- [ ] 点击入口进入美颜设置页面，相机预览正常显示
- [ ] 调整美颜参数后返回，再进入，参数已保留