import 'dart:typed_data';
import 'package:flutter/services.dart';

class MtPlugin {
  static const MethodChannel _channel = MethodChannel('mt_plugin');
  static const MethodChannel _beautyChannel = MethodChannel('beauty_plugin');

  static bool _shouldPushToAgora = false;

  static void setRenderEnable(bool enable) {
    _channel.invokeMethod('SET_RENDER_ENABLE', {'enable': enable});
  }

  static void setFaceBeautyEnable(bool enable) {
    _channel.invokeMethod('SET_FACE_BEAUTY_ENABLE', {'enable': enable});
  }

  static void setWhitenessValue(int value) {
    _channel.invokeMethod('SET_WHITENESS_VALUE', {'value': value});
  }

  static void setBlurrinessValue(int value) {
    _channel.invokeMethod('SET_BLURRINESS_VALUE', {'value': value});
  }

  static void setRosinessValue(int value) {
    _channel.invokeMethod('SET_ROSINESS_VALUE', {'value': value});
  }

  static void setClearnessValue(int value) {
    _channel.invokeMethod('SET_CLEAR_NESS_VALUE', {'value': value});
  }

  static void setBrightnessValue(int value) {
    _channel.invokeMethod('SET_BRIGHTNESS_VALUE', {'value': value});
  }

  static void setUndereyeCirclesValue(int value) {
    _channel.invokeMethod('SET_UNDEREYE_CIRCLES_VALUE', {'value': value});
  }

  static void setNasolabialFoldValue(int value) {
    _channel.invokeMethod('SET_NASOLABIAL_FOLD_VALUE', {'value': value});
  }

  static void setFaceShapeEnable(bool enable) {
    _channel.invokeMethod('SET_FACE_SHAPE_ENABLE', {'value': enable});
  }

  static void setEyeEnlargingValue(int value) {
    _channel.invokeMethod('SET_EYE_ENLARGING_VALUE', {'value': value});
  }

  static void setEyeRoundingValue(int value) {
    _channel.invokeMethod('SET_EYE_ROUNDING_VALUE', {'value': value});
  }

  static void setCheekThinningValue(int value) {
    _channel.invokeMethod('SET_CHEEK_THINNING_VALUE', {'value': value});
  }

  static void setCheekVValue(int value) {
    _channel.invokeMethod('SET_CHEEK_V_VALUE', {'value': value});
  }

  static void setCheekNarrowingValue(int value) {
    _channel.invokeMethod('SET_CHEEK_NARROWING_VALUE', {'value': value});
  }

  static void setChinTrimmingValue(int value) {
    _channel.invokeMethod('SET_CHIN_TRIMMING_VALUE', {'value': value});
  }

  static void setForeheadTrimmingValue(int value) {
    _channel.invokeMethod('SET_FOREHEAD_TRIMMING_VALUE', {'value': value});
  }

  static void setNoseThinningValue(int value) {
    _channel.invokeMethod('SET_NOSE_THINNING_VALUE', {'value': value});
  }

  static void setNoseEnlargingValue(int value) {
    _channel.invokeMethod('SET_NOSE_ENLARGING_VALUE', {'value': value});
  }

  static void setEyeSpacingTrimmingValue(int value) {
    _channel.invokeMethod('SET_EYE_SPACING_TRIMMING_VALUE', {'value': value});
  }

  static void setEyeCornerTrimmingValue(int value) {
    _channel.invokeMethod('SET_EYE_CORNER_TRIMMING_VALUE', {'value': value});
  }

  static void setPhiltrumTrimmingValue(int value) {
    _channel.invokeMethod('SET_PHILTRUM_TRIMMING_VALUE', {'value': value});
  }

  static void setNoseApexLesseningValue(int value) {
    _channel.invokeMethod('SET_NOSE_APEX_LESSENING_VALUE', {'value': value});
  }

  static void setNoseRootEnlargingValue(int value) {
    _channel.invokeMethod('SET_NOSE_ROOT_RNLARING', {'value': value});
  }

  static void setTempleEnlargingValue(int value) {
    _channel.invokeMethod('SET_TEMPLE_ENLARG_ING_VALUE', {'value': value});
  }

  static void setFaceLesseningValue(int value) {
    _channel.invokeMethod('SET_FACE_LESSENING_VALUE', {'value': value});
  }

  static void setFaceShorteningValue(int value) {
    _channel.invokeMethod('SET_FACE_SHORTENING_VALUE', {'value': value});
  }

  static void setHeadLesseningValue(int value) {
    _channel.invokeMethod('SET_HEAD_LESSENING_VALUE', {'value': value});
  }

  static void setMouthTrimmingValue(int value) {
    _channel.invokeMethod('SET_MOUTH_TRIMMING_VALUE', {'value': value});
  }

  static void setMouthSmilingEnlargingValue(int value) {
    _channel.invokeMethod('SET_MOUTH_SMILING_ENLARGING_VALUE', {'value': value});
  }

  static void setJawBoneThinningValue(int value) {
    _channel.invokeMethod('SET_JAW_BONE_THINNING_VALUE', {'value': value});
  }

  static void setCheekBoneThinningValue(int value) {
    _channel.invokeMethod('SET_CHEEK_BONE_THINNING', {'value': value});
  }

  static void setDynamicStickerName(String name) {
    _channel.invokeMethod('SET_DYNAMIC_STICKER_NAME', {'name': name});
  }

  static void setMaskName(String name) {
    _channel.invokeMethod('SET_MASK_NAME', {'name': name});
  }

  static void setGiftName(String name) {
    _channel.invokeMethod('SET_GIFT_NAME', {'name': name});
  }

  static void setWatermarkName(String name) {
    _channel.invokeMethod('SET_WATERMARK_NAME', {'name': name});
  }

  static void setAtmosphereItemName(String name) {
    _channel.invokeMethod('SET_ATMOSPHERE_ITEM_NAME', {'name': name});
  }

  static void setBeautyFilterName(String name, int intensity) {
    _channel.invokeMethod('SET_BEAUTY_FILTER_NAME', {
      'name': name,
      'value': intensity,
    });
  }

  static void setEffectFilterName(String name, int intensity) {
    _channel.invokeMethod('SET_EFFECT_FILTER_TYPE', {
      'name': name,
      'progress': intensity,
    });
  }

  static void setFunnyFilterName(String name) {
    _channel.invokeMethod('SET_FUNNY_FILTER_TYPE', {'name': name});
  }

  static void setPortraitName(String name) {
    _channel.invokeMethod('SET_PORTRAIT_NAME', {'name': name});
  }

  static void initSdk(String key) {
    _channel.invokeMethod('INIT_SDK', {'key': key});
  }

  static Future<Map<String, String>> initPath() async {
    final result = await _channel.invokeMethod<Map>('INIT_PATH');
    if (result == null) return {};
    return result.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  static void startAgoraPush() {
    _shouldPushToAgora = true;
    _beautyChannel.invokeMethod('startAgoraPush');
  }

  static void stopAgoraPush() {
    _shouldPushToAgora = false;
    _beautyChannel.invokeMethod('stopAgoraPush');
  }

  static bool get shouldPushToAgora => _shouldPushToAgora;

  static void Function(int width, int height, int stride, Uint8List bytes)?
      onFrameCallback;
}
