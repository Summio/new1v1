import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import 'api_interceptor.dart';
import 'api_exception.dart';

/// Dio HTTP 客户端
/// 封装 GET/POST 方法，统一错误处理
class DioClient {
  DioClient._();

  static final DioClient _instance = DioClient._();
  static DioClient get instance => _instance;

  late final Dio _dio;
  late final ApiInterceptor _apiInterceptor;

  Dio get dio => _dio;

  /// 初始化（App 启动时调用一次）
  void init({
    ApiRequestTransformer? requestTransformer,
  }) {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: const Duration(milliseconds: AppConstants.connectTimeoutMs),
        receiveTimeout: const Duration(milliseconds: AppConstants.receiveTimeoutMs),
        sendTimeout: const Duration(milliseconds: AppConstants.sendTimeoutMs),
        responseType: ResponseType.json,
      ),
    );

    _apiInterceptor = ApiInterceptor(
      requestTransformer: requestTransformer,
      enableDebugLog: kDebugMode,
    );

    _dio.interceptors.add(_apiInterceptor);
  }

  // =============== 通用请求方法 ===============

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.put<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.delete<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // =============== API 方法 ===============

  /// GET 请求
  Future<Map<String, dynamic>> apiGet(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    final resp = await get<Map<String, dynamic>>(
      path,
      queryParameters: params,
    );
    return resp.data ?? {};
  }

  /// POST 请求
  Future<Map<String, dynamic>> apiPost(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final resp = await post<Map<String, dynamic>>(
      path,
      data: data,
    );
    return resp.data ?? {};
  }

  /// PUT 请求
  Future<Map<String, dynamic>> apiPut(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final resp = await put<Map<String, dynamic>>(path, data: data);
    return resp.data ?? {};
  }

  // =============== 错误处理 ===============

  Exception _handleError(DioException e) {
    if (e.error is ApiException) {
      return e.error as ApiException;
    }
    if (e.error is NetworkException) {
      return e.error as NetworkException;
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return const NetworkException('请求超时，请稍后重试');
    }
    if (e.type == DioExceptionType.connectionError) {
      return const NetworkException('网络连接失败，请检查网络');
    }
    return NetworkException(e.message ?? '网络请求失败');
  }
}
