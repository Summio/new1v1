import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static String? _tokenCache;

  /// 初始化（App 启动时调用一次）
  static Future<void> init() async {
    await Hive.initFlutter();

    _prefs = await SharedPreferences.getInstance();
    _userBox = await Hive.openBox(AppConstants.hiveBoxUser);
    _cacheBox = await Hive.openBox(AppConstants.hiveBoxCache);
    await _migrateTokenToSecureStorage();
  }

  // =============== SharedPreferences（键值对） ===============

  /// 保存 Token
  static Future<void> saveToken(String token) async {
    _tokenCache = token;
    await _secureStorage.write(key: AppConstants.storageToken, value: token);
    await _prefs?.remove(AppConstants.storageToken);
  }

  /// 获取 Token
  static String? getToken() {
    return _tokenCache;
  }

  /// 删除 Token
  static Future<void> removeToken() async {
    _tokenCache = null;
    await _secureStorage.delete(key: AppConstants.storageToken);
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

  static bool isMessageSoundEnabled() {
    return getBool(AppConstants.storageMessageSoundEnabled) ?? true;
  }

  static Future<void> setMessageSoundEnabled(bool enabled) async {
    await saveBool(AppConstants.storageMessageSoundEnabled, enabled);
  }

  static bool isIncomingRingtoneEnabled() {
    return getBool(AppConstants.storageIncomingRingtoneEnabled) ?? true;
  }

  static Future<void> setIncomingRingtoneEnabled(bool enabled) async {
    await saveBool(AppConstants.storageIncomingRingtoneEnabled, enabled);
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
    _tokenCache = null;
    await _secureStorage.delete(key: AppConstants.storageToken);
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

  /// 保存认证用户列表缓存
  static Future<void> saveCertifiedUserList(
    List<Map<String, dynamic>> certifiedUsers,
  ) async {
    await _cacheBox?.put(AppConstants.storageCertifiedUserList, certifiedUsers);
  }

  /// 获取认证用户列表缓存
  static List<Map<String, dynamic>>? getCertifiedUserList() {
    final data = _cacheBox?.get(AppConstants.storageCertifiedUserList);
    if (data == null) return null;
    return List<Map<String, dynamic>>.from(
      (data as List).map((e) => Map<String, dynamic>.from(e)),
    );
  }

  /// 清空所有用户数据（退出登录时调用）
  static Future<void> clearUserData() async {
    await removeToken();
    await _prefs?.remove(AppConstants.storageUserId);
    await _prefs?.remove(AppConstants.storageInitialProfileCompleted);
    await _userBox?.clear();
  }

  static Future<void> _migrateTokenToSecureStorage() async {
    final secureToken = await _secureStorage.read(
      key: AppConstants.storageToken,
    );
    if (secureToken != null && secureToken.isNotEmpty) {
      _tokenCache = secureToken;
      await _prefs?.remove(AppConstants.storageToken);
      return;
    }

    final legacyToken = _prefs?.getString(AppConstants.storageToken);
    if (legacyToken != null && legacyToken.isNotEmpty) {
      await _secureStorage.write(
        key: AppConstants.storageToken,
        value: legacyToken,
      );
      await _prefs?.remove(AppConstants.storageToken);
      _tokenCache = legacyToken;
      return;
    }

    _tokenCache = null;
  }
}
