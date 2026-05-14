import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';

class CertifiedCommonPhraseInfo {
  final int? id;
  final int slotIndex;
  final String approvedContent;
  final String pendingContent;
  final String reviewStatus;
  final String reviewRemark;

  const CertifiedCommonPhraseInfo({
    this.id,
    required this.slotIndex,
    this.approvedContent = '',
    this.pendingContent = '',
    this.reviewStatus = 'none',
    this.reviewRemark = '',
  });

  factory CertifiedCommonPhraseInfo.empty(int slotIndex) {
    return CertifiedCommonPhraseInfo(slotIndex: slotIndex);
  }

  factory CertifiedCommonPhraseInfo.fromJson(Map<String, dynamic> json) {
    return CertifiedCommonPhraseInfo(
      id: (json['id'] as num?)?.toInt(),
      slotIndex: (json['slot_index'] as num?)?.toInt() ?? 0,
      approvedContent: (json['approved_content'] as String?)?.trim() ?? '',
      pendingContent: (json['pending_content'] as String?)?.trim() ?? '',
      reviewStatus: (json['review_status'] as String?)?.trim() ?? 'none',
      reviewRemark: (json['review_remark'] as String?)?.trim() ?? '',
    );
  }
}

class CertifiedCommonPhrasesState {
  final List<CertifiedCommonPhraseInfo> phrases;
  final bool isLoading;
  final String? error;

  const CertifiedCommonPhrasesState({
    this.phrases = const [],
    this.isLoading = false,
    this.error,
  });

  int get approvedCount =>
      phrases.where((item) => item.approvedContent.isNotEmpty).length;

  int get pendingCount =>
      phrases.where((item) => item.reviewStatus == 'pending').length;

  CertifiedCommonPhrasesState copyWith({
    List<CertifiedCommonPhraseInfo>? phrases,
    bool? isLoading,
    String? error,
  }) {
    return CertifiedCommonPhrasesState(
      phrases: phrases ?? this.phrases,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class CertifiedCommonPhrasesNotifier
    extends StateNotifier<CertifiedCommonPhrasesState> {
  final DioClient _dio;

  CertifiedCommonPhrasesNotifier(this._dio)
    : super(const CertifiedCommonPhrasesState());

  Future<void> fetch() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final resp = await _dio.apiGet(ApiEndpoints.certifiedCommonPhrases);
      final data = resp['data'] as Map<String, dynamic>? ?? {};
      final raw = data['phrases'] as List? ?? const [];
      final parsed = raw
          .whereType<Map<String, dynamic>>()
          .map(CertifiedCommonPhraseInfo.fromJson)
          .toList();
      final bySlot = {for (final item in parsed) item.slotIndex: item};
      state = CertifiedCommonPhrasesState(
        phrases: List.generate(
          3,
          (index) =>
              bySlot[index + 1] ?? CertifiedCommonPhraseInfo.empty(index + 1),
        ),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '加载常用语失败');
    }
  }

  Future<void> submit({required int slotIndex, required String content}) async {
    await _dio.apiPut(
      '${ApiEndpoints.certifiedCommonPhrases}/$slotIndex',
      data: {'content': content},
    );
    await fetch();
  }
}

final certifiedCommonPhrasesProvider =
    StateNotifierProvider<
      CertifiedCommonPhrasesNotifier,
      CertifiedCommonPhrasesState
    >((ref) {
      return CertifiedCommonPhrasesNotifier(DioClient.instance);
    });
