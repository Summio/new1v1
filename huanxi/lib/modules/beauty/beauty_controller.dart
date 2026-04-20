import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mt_plugin/mt_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';

typedef BeautyLogCallback = void Function(String message);

class BeautyState {
  final bool isBeautyEnabled;
  final bool isFaceShapeEnabled;
  final bool isRenderEnabled;

  // 美颜参数 [0-100]
  final int whitening;
  final int blurriness;
  final int rosiness;
  final int clearness;
  final int brightness;

  // 美型参数 [0-100]
  final int eyeEnlarging;
  final int eyeRounding;
  final int cheekThinning;
  final int cheekV;
  final int cheekNarrowing;
  final int chin;
  final int forehead;
  final int noseThinning;

  // 滤镜
  final String? currentFilter;
  final int filterIntensity;

  const BeautyState({
    this.isBeautyEnabled = true,
    this.isFaceShapeEnabled = false,
    this.isRenderEnabled = true,
    this.whitening = 50,
    this.blurriness = 50,
    this.rosiness = 20,
    this.clearness = 10,
    this.brightness = 0,
    this.eyeEnlarging = 0,
    this.eyeRounding = 0,
    this.cheekThinning = 0,
    this.cheekV = 0,
    this.cheekNarrowing = 0,
    this.chin = 0,
    this.forehead = 0,
    this.noseThinning = 0,
    this.currentFilter,
    this.filterIntensity = 60,
  });

  BeautyState copyWith({
    bool? isBeautyEnabled,
    bool? isFaceShapeEnabled,
    bool? isRenderEnabled,
    int? whitening,
    int? blurriness,
    int? rosiness,
    int? clearness,
    int? brightness,
    int? eyeEnlarging,
    int? eyeRounding,
    int? cheekThinning,
    int? cheekV,
    int? cheekNarrowing,
    int? chin,
    int? forehead,
    int? noseThinning,
    Object? currentFilter = const _NoValue(),
    int? filterIntensity,
  }) {
    return BeautyState(
      isBeautyEnabled: isBeautyEnabled ?? this.isBeautyEnabled,
      isFaceShapeEnabled: isFaceShapeEnabled ?? this.isFaceShapeEnabled,
      isRenderEnabled: isRenderEnabled ?? this.isRenderEnabled,
      whitening: whitening ?? this.whitening,
      blurriness: blurriness ?? this.blurriness,
      rosiness: rosiness ?? this.rosiness,
      clearness: clearness ?? this.clearness,
      brightness: brightness ?? this.brightness,
      eyeEnlarging: eyeEnlarging ?? this.eyeEnlarging,
      eyeRounding: eyeRounding ?? this.eyeRounding,
      cheekThinning: cheekThinning ?? this.cheekThinning,
      cheekV: cheekV ?? this.cheekV,
      cheekNarrowing: cheekNarrowing ?? this.cheekNarrowing,
      chin: chin ?? this.chin,
      forehead: forehead ?? this.forehead,
      noseThinning: noseThinning ?? this.noseThinning,
      currentFilter: identical(currentFilter, const _NoValue())
          ? this.currentFilter
          : (currentFilter as String?),
      filterIntensity: filterIntensity ?? this.filterIntensity,
    );
  }
}

class _NoValue {
  const _NoValue();
}

class BeautyController extends StateNotifier<BeautyState> {
  final BeautyLogCallback? onLog;
  SharedPreferences? _prefs;

  BeautyController({this.onLog}) : super(const BeautyState()) {
    _log('BeautyController init');
    _syncToNative();
    Future.microtask(() async {
      await _loadFromStorage();
      _syncToNative();
    });
  }

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

  void _syncToNative() {
    _log('sync beauty params: whitening=${state.whitening}, blurriness=${state.blurriness}');
    MtPlugin.setRenderEnable(state.isRenderEnabled);
    MtPlugin.setFaceBeautyEnable(state.isBeautyEnabled);
    MtPlugin.setWhitenessValue(state.whitening);
    MtPlugin.setBlurrinessValue(state.blurriness);
    MtPlugin.setRosinessValue(state.rosiness);
    MtPlugin.setClearnessValue(state.clearness);
    MtPlugin.setBrightnessValue(state.brightness);
    MtPlugin.setEyeEnlargingValue(state.eyeEnlarging);
    MtPlugin.setEyeRoundingValue(state.eyeRounding);
    MtPlugin.setCheekThinningValue(state.cheekThinning);
    MtPlugin.setCheekVValue(state.cheekV);
    MtPlugin.setCheekNarrowingValue(state.cheekNarrowing);
    MtPlugin.setFaceShapeEnable(state.isFaceShapeEnabled);
    if (state.currentFilter != null && state.currentFilter!.isNotEmpty) {
      MtPlugin.setBeautyFilterName(state.currentFilter!, state.filterIntensity);
    }
  }

  void _log(String msg) {
    if (onLog != null) {
      onLog!('[Beauty] $msg');
    } else if (kDebugMode) {
      debugPrint('[Beauty] $msg');
    }
  }

  void _update(BeautyState Function(BeautyState) updater) {
    state = updater(state);
    _syncToNative();
    _saveToStorage();
  }

  void toggleRender() {
    _log('toggle render: ${!state.isRenderEnabled}');
    _update((s) => s.copyWith(isRenderEnabled: !s.isRenderEnabled));
  }

  void toggleBeauty() {
    _log('toggle beauty: ${!state.isBeautyEnabled}');
    _update((s) => s.copyWith(isBeautyEnabled: !s.isBeautyEnabled));
  }

  void toggleFaceShape() {
    _log('toggle faceShape: ${!state.isFaceShapeEnabled}');
    _update((s) => s.copyWith(isFaceShapeEnabled: !s.isFaceShapeEnabled));
  }

  void setWhitening(int v) {
    _log('set whitening: $v');
    _update((s) => s.copyWith(whitening: v.clamp(0, 100)));
  }

  void setBlurriness(int v) {
    _log('set blurriness: $v');
    _update((s) => s.copyWith(blurriness: v.clamp(0, 100)));
  }

  void setRosiness(int v) {
    _log('set rosiness: $v');
    _update((s) => s.copyWith(rosiness: v.clamp(0, 100)));
  }

  void setClearness(int v) {
    _log('set clearness: $v');
    _update((s) => s.copyWith(clearness: v.clamp(0, 100)));
  }

  void setBrightness(int v) {
    _log('set brightness: $v');
    _update((s) => s.copyWith(brightness: v.clamp(0, 100)));
  }

  void setEyeEnlarging(int v) {
    _log('set eyeEnlarging: $v');
    _update((s) => s.copyWith(eyeEnlarging: v.clamp(0, 100)));
  }

  void setEyeRounding(int v) {
    _log('set eyeRounding: $v');
    _update((s) => s.copyWith(eyeRounding: v.clamp(0, 100)));
  }

  void setCheekThinning(int v) {
    _log('set cheekThinning: $v');
    _update((s) => s.copyWith(cheekThinning: v.clamp(0, 100)));
  }

  void setCheekV(int v) {
    _log('set cheekV: $v');
    _update((s) => s.copyWith(cheekV: v.clamp(0, 100)));
  }

  void setCheekNarrowing(int v) {
    _log('set cheekNarrowing: $v');
    _update((s) => s.copyWith(cheekNarrowing: v.clamp(0, 100)));
  }

  void setChin(int v) {
    _log('set chin: $v');
    _update((s) => s.copyWith(chin: v.clamp(0, 100)));
  }

  void setForehead(int v) {
    _log('set forehead: $v');
    _update((s) => s.copyWith(forehead: v.clamp(0, 100)));
  }

  void setNoseThinning(int v) {
    _log('set noseThinning: $v');
    _update((s) => s.copyWith(noseThinning: v.clamp(0, 100)));
  }

  void setFilter(String? name, [int intensity = 60]) {
    _log('set filter: name=$name, intensity=$intensity');
    _update((s) => s.copyWith(currentFilter: name, filterIntensity: intensity));
  }

  void resetBeauty() {
    _log('reset beauty params');
    _update((s) => s.copyWith(
      whitening: 50,
      blurriness: 50,
      rosiness: 20,
      clearness: 10,
      brightness: 0,
    ));
  }

  void resetFaceShape() {
    _log('reset face shape params');
    _update((s) => s.copyWith(
      eyeEnlarging: 0,
      eyeRounding: 0,
      cheekThinning: 0,
      cheekV: 0,
      cheekNarrowing: 0,
      chin: 0,
      forehead: 0,
      noseThinning: 0,
    ));
  }
}

final beautyControllerProvider =
    StateNotifierProvider.autoDispose<BeautyController, BeautyState>(
  (_) => BeautyController(),
);

// 预设滤镜列表（精选常用滤镜）
const beautyFilters = [
  (label: '原图', name: ''),
  (label: '自然1', name: 'ziran1'),
  (label: '自然2', name: 'ziran2'),
  (label: '自然3', name: 'ziran3'),
  (label: '自然4', name: 'ziran4'),
  (label: '自然5', name: 'ziran5'),
  (label: '质感1', name: 'zhigan1'),
  (label: '质感2', name: 'zhigan2'),
  (label: '质感3', name: 'zhigan3'),
  (label: '白兰', name: 'bailan'),
  (label: '纯真', name: 'chunzhen'),
  (label: '清新', name: 'qingxin'),
  (label: '柔光', name: 'rouguang'),
  (label: '复古', name: 'fugu'),
];
