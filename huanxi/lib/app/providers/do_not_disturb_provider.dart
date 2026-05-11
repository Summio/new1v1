import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import 'auth_provider.dart';

class DoNotDisturbSettings {
  final bool textDndEnabled;
  final bool videoDndEnabled;
  final bool rankingInvisibleEnabled;

  const DoNotDisturbSettings({
    this.textDndEnabled = false,
    this.videoDndEnabled = false,
    this.rankingInvisibleEnabled = false,
  });

  factory DoNotDisturbSettings.fromJson(Map<String, dynamic> json) {
    return DoNotDisturbSettings(
      textDndEnabled: json['text_dnd_enabled'] == true,
      videoDndEnabled: json['video_dnd_enabled'] == true,
      rankingInvisibleEnabled: json['ranking_invisible_enabled'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text_dnd_enabled': textDndEnabled,
      'video_dnd_enabled': videoDndEnabled,
      'ranking_invisible_enabled': rankingInvisibleEnabled,
    };
  }

  DoNotDisturbSettings copyWith({
    bool? textDndEnabled,
    bool? videoDndEnabled,
    bool? rankingInvisibleEnabled,
  }) {
    return DoNotDisturbSettings(
      textDndEnabled: textDndEnabled ?? this.textDndEnabled,
      videoDndEnabled: videoDndEnabled ?? this.videoDndEnabled,
      rankingInvisibleEnabled:
          rankingInvisibleEnabled ?? this.rankingInvisibleEnabled,
    );
  }
}

class DoNotDisturbState {
  final DoNotDisturbSettings settings;
  final bool isLoading;
  final bool isSaving;
  final String? error;

  const DoNotDisturbState({
    this.settings = const DoNotDisturbSettings(),
    this.isLoading = false,
    this.isSaving = false,
    this.error,
  });

  DoNotDisturbState copyWith({
    DoNotDisturbSettings? settings,
    bool? isLoading,
    bool? isSaving,
    String? error,
  }) {
    return DoNotDisturbState(
      settings: settings ?? this.settings,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      error: error,
    );
  }
}

class DoNotDisturbNotifier extends StateNotifier<DoNotDisturbState> {
  DoNotDisturbNotifier(this._ref) : super(const DoNotDisturbState());

  final Ref _ref;
  final DioClient _dio = DioClient.instance;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.apiGet(ApiEndpoints.doNotDisturbSettings);
      final data = response['data'] as Map<String, dynamic>? ?? {};
      state = state.copyWith(
        settings: DoNotDisturbSettings.fromJson(data),
        isLoading: false,
        error: null,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false, error: '勿扰设置加载失败');
      rethrow;
    }
  }

  Future<void> update(
    DoNotDisturbSettings next, {
    required DoNotDisturbSettings previous,
  }) async {
    state = state.copyWith(settings: next, isSaving: true, error: null);
    try {
      final response = await _dio.apiPut(
        ApiEndpoints.doNotDisturbSettings,
        data: next.toJson(),
      );
      final data = response['data'] as Map<String, dynamic>? ?? {};
      state = state.copyWith(
        settings: DoNotDisturbSettings.fromJson(data),
        isSaving: false,
        error: null,
      );
      await _ref.read(authProvider.notifier).fetchUserInfo();
    } catch (_) {
      rollback(previous);
      rethrow;
    }
  }

  void rollback(DoNotDisturbSettings previous) {
    state = state.copyWith(
      settings: previous,
      isSaving: false,
      error: '勿扰设置保存失败',
    );
  }
}

final doNotDisturbProvider =
    StateNotifierProvider<DoNotDisturbNotifier, DoNotDisturbState>((ref) {
      return DoNotDisturbNotifier(ref);
    });
