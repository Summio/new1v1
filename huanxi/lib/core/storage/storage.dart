import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

/// 本地存储服务
/// 统一封装 shared_preferences（键值对）和 Hive（结构化数据）
class StorageService {
  StorageService._();

  static SharedPreferences? _prefs;
  static Box? _userBox;
  static Box? _cacheBox;

  /// 初始化（App 启动时调用一次）
  static Future<void> init() async {
    await Hive.initFlutter();

    _prefs = await SharedPreferences.getInstance();
    _userBox = await Hive.openBox(AppConstants.hiveBoxUser);
    _cacheBox = await Hive.openBox(AppConstants.hiveBoxCache);
  }

  // =============== SharedPreferences（键值对） ===============

  /// 保存 Token
  static Future<void> saveToken(String token) async {
    await _prefs?.setString(AppConstants.storageToken, token);
  }

  /// 获取 Token
  static String? getToken() {
    return _prefs?.getString(AppConstants.storageToken);
  }

  /// 删除 Token
  static Future<void> removeToken() async {
    await _prefs?.remove(AppConstants.storageToken);
  }

  /// 保存用户 ID
  static Future<void> saveUserId(int userId) async {
    await _prefs?.setInt(AppConstants.storageUserId, userId);
  }

  /// 获取用户 ID
  static int? getUserId() {
    return _prefs?.getInt(AppConstants.storageUserId);
  }

  /// 保存布尔值
  static Future<void> saveBool(String key, bool value) async {
    await _prefs?.setBool(key, value);
  }

  /// 获取布尔值
  static bool? getBool(String key) {
    return _prefs?.getBool(key);
  }

  /// 保存字符串
  static Future<void> saveString(String key, String value) async {
    await _prefs?.setString(key, value);
  }

  /// 获取字符串
  static String? getString(String key) {
    return _prefs?.getString(key);
  }

  /// 删除某个 key
  static Future<void> remove(String key) async {
    await _prefs?.remove(key);
  }

  /// 清空所有 shared_preferences
  static Future<void> clearAll() async {
    await _prefs?.clear();
  }

  // =============== Hive（结构化数据） ===============

  /// 保存用户信息（JSON 字符串）
  static Future<void> saveUserInfo(Map<String, dynamic> userInfo) async {
    await _userBox?.put(AppConstants.storageUserInfo, userInfo);
  }

  /// 获取用户信息
  static Map<String, dynamic>? getUserInfo() {
    final data = _userBox?.get(AppConstants.storageUserInfo);
    if (data == null) return null;
    return Map<String, dynamic>.from(data);
  }

  /// 保存礼物列表（JSON 字符串）
  static Future<void> saveGiftList(List<Map<String, dynamic>> gifts) async {
    await _cacheBox?.put(AppConstants.storageGiftList, gifts);
  }

  /// 获取礼物列表
  static List<Map<String, dynamic>>? getGiftList() {
    final data = _cacheBox?.get(AppConstants.storageGiftList);
    if (data == null) return null;
    return List<Map<String, dynamic>>.from(
      (data as List).map((e) => Map<String, dynamic>.from(e)),
    );
  }

  /// 保存主播列表缓存
  static Future<void> saveAnchorList(List<Map<String, dynamic>> anchors) async {
    await _cacheBox?.put(AppConstants.storageAnchorList, anchors);
  }

  /// 获取主播列表缓存
  static List<Map<String, dynamic>>? getAnchorList() {
    final data = _cacheBox?.get(AppConstants.storageAnchorList);
    if (data == null) return null;
    return List<Map<String, dynamic>>.from(
      (data as List).map((e) => Map<String, dynamic>.from(e)),
    );
  }

  /// 清空所有用户数据（退出登录时调用）
  static Future<void> clearUserData() async {
    await _prefs?.remove(AppConstants.storageToken);
    await _prefs?.remove(AppConstants.storageUserId);
    await _userBox?.clear();
  }
}
