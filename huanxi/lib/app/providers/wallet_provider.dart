import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/media/image_upload_preprocessor.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../app/providers/auth_provider.dart';

/// 交易记录类型
enum TransactionType { all, income, expense }

double parseDouble(dynamic value, {double fallback = 0}) {
  if (value is int) return value.toDouble();
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? fallback;
  return fallback;
}

/// 单条交易记录
class TransactionRecord {
  final String id;
  final String type;
  final String title;
  final double amount;
  final bool isIncome;
  final String createdAt;

  const TransactionRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.amount,
    required this.isIncome,
    required this.createdAt,
  });

  factory TransactionRecord.fromJson(Map<String, dynamic> json) {
    return TransactionRecord(
      id: (json['id'] ?? '').toString(),
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      amount: parseDouble(json['amount']),
      isIncome: json['is_income'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

/// 钱包状态
class WalletState {
  final double coins;
  final double diamonds;
  final double frozenDiamonds;
  final List<TransactionRecord> transactions;
  final int total;
  final int currentPage;
  final bool hasMore;
  final TransactionType filterType;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  const WalletState({
    this.coins = 0,
    this.diamonds = 0,
    this.frozenDiamonds = 0,
    this.transactions = const [],
    this.total = 0,
    this.currentPage = 1,
    this.hasMore = false,
    this.filterType = TransactionType.all,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  WalletState copyWith({
    double? coins,
    double? diamonds,
    double? frozenDiamonds,
    List<TransactionRecord>? transactions,
    int? total,
    int? currentPage,
    bool? hasMore,
    TransactionType? filterType,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
  }) {
    return WalletState(
      coins: coins ?? this.coins,
      diamonds: diamonds ?? this.diamonds,
      frozenDiamonds: frozenDiamonds ?? this.frozenDiamonds,
      transactions: transactions ?? this.transactions,
      total: total ?? this.total,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      filterType: filterType ?? this.filterType,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error ?? this.error,
    );
  }
}

/// 提现请求结果
class WithdrawResult {
  final double diamonds;
  final double frozenDiamonds;
  final String msg;

  const WithdrawResult({
    required this.diamonds,
    required this.frozenDiamonds,
    required this.msg,
  });

  factory WithdrawResult.fromJson(Map<String, dynamic> json) {
    return WithdrawResult(
      diamonds: parseDouble(json['diamonds']),
      frozenDiamonds: parseDouble(json['frozen_diamonds']),
      msg: json['msg'] as String? ?? '',
    );
  }
}

class WithdrawAccount {
  final String realName;
  final String accountNo;
  final String paymentQrCode;
  final bool hasAccount;
  final String status;
  final String reviewRemark;
  final String reviewedAt;
  final bool canWithdraw;

  const WithdrawAccount({
    this.realName = '',
    this.accountNo = '',
    this.paymentQrCode = '',
    this.hasAccount = false,
    this.status = '',
    this.reviewRemark = '',
    this.reviewedAt = '',
    this.canWithdraw = false,
  });

  factory WithdrawAccount.fromJson(Map<String, dynamic> json) {
    return WithdrawAccount(
      realName: (json['real_name'] as String?)?.trim() ?? '',
      accountNo: (json['account_no'] as String?)?.trim() ?? '',
      paymentQrCode: (json['payment_qr_code'] as String?)?.trim() ?? '',
      hasAccount: json['has_account'] == true,
      status: (json['status'] as String?)?.trim() ?? '',
      reviewRemark: (json['review_remark'] as String?)?.trim() ?? '',
      reviewedAt: (json['reviewed_at'] as String?)?.trim() ?? '',
      canWithdraw: json['can_withdraw'] == true,
    );
  }

  bool get isComplete =>
      realName.isNotEmpty && accountNo.isNotEmpty && paymentQrCode.isNotEmpty;

  bool get isPending => status == 'pending';

  bool get isApproved => status == 'approved';

  bool get isRejected => status == 'rejected';
}

/// 钱包 Provider
class WalletNotifier extends StateNotifier<WalletState> {
  final DioClient _dio;
  final Ref _ref;

  WalletNotifier(this._dio, this._ref) : super(const WalletState());

  /// 获取余额
  Future<void> fetchBalance() async {
    try {
      final data = await _dio.apiGet(ApiEndpoints.walletBalance);
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) return;

      state = state.copyWith(
        coins: parseDouble(respData['coins']),
        diamonds: parseDouble(respData['diamonds']),
        frozenDiamonds: parseDouble(respData['frozen_diamonds']),
      );

      _ref
          .read(authProvider.notifier)
          .syncBalance(coins: state.coins, diamonds: state.diamonds);
    } catch (e) {
      AppLogger.debug('wallet.fetchBalance error: $e');
    }
  }

  /// 获取交易记录（第一页或切换 filter）
  Future<void> fetchTransactions({TransactionType? type}) async {
    if (type != null) {
      state = state.copyWith(
        filterType: type,
        isLoading: true,
        transactions: [],
      );
    } else {
      state = state.copyWith(isLoading: true);
    }

    try {
      final typeStr = type == TransactionType.income
          ? 'income'
          : type == TransactionType.expense
          ? 'expense'
          : 'all';
      final data = await _dio.apiGet(
        ApiEndpoints.walletTransactions,
        params: {'type': typeStr, 'page': 1, 'page_size': 20},
      );
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final records =
          (respData['records'] as List<dynamic>?)
              ?.map(
                (e) => TransactionRecord.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [];

      state = state.copyWith(
        transactions: records,
        total: respData['total'] as int? ?? 0,
        currentPage: 1,
        hasMore: respData['has_more'] as bool? ?? false,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      AppLogger.debug('wallet.fetchTransactions error: $e');
      state = state.copyWith(isLoading: false, error: '账单加载失败，请稍后重试');
    }
  }

  /// 加载更多
  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final typeStr = state.filterType == TransactionType.income
          ? 'income'
          : state.filterType == TransactionType.expense
          ? 'expense'
          : 'all';
      final nextPage = state.currentPage + 1;
      final data = await _dio.apiGet(
        ApiEndpoints.walletTransactions,
        params: {'type': typeStr, 'page': nextPage, 'page_size': 20},
      );
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) {
        state = state.copyWith(isLoadingMore: false);
        return;
      }

      final newRecords =
          (respData['records'] as List<dynamic>?)
              ?.map(
                (e) => TransactionRecord.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [];

      state = state.copyWith(
        transactions: [...state.transactions, ...newRecords],
        currentPage: nextPage,
        hasMore: respData['has_more'] as bool? ?? false,
        isLoadingMore: false,
      );
    } catch (e) {
      AppLogger.debug('wallet.loadMore error: $e');
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// 提现申请
  Future<WithdrawResult?> withdraw({required int amount}) async {
    try {
      final data = await _dio.apiPost(
        ApiEndpoints.withdrawApply,
        data: {'amount': amount, 'bank_name': '支付宝'},
      );
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) return null;

      final result = WithdrawResult.fromJson(respData);

      // 更新本地余额
      state = state.copyWith(
        diamonds: result.diamonds,
        frozenDiamonds: result.frozenDiamonds,
      );

      // 同步更新 AuthState
      _ref.read(authProvider.notifier).refreshBalance();

      return result;
    } catch (e) {
      AppLogger.debug('wallet.withdraw error: $e');
      return null;
    }
  }

  Future<WithdrawAccount?> fetchWithdrawAccount() async {
    try {
      final data = await _dio.apiGet(ApiEndpoints.withdrawAccount);
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) return const WithdrawAccount();
      return WithdrawAccount.fromJson(respData);
    } catch (e) {
      AppLogger.debug('wallet.fetchWithdrawAccount error: $e');
      return null;
    }
  }

  Future<WithdrawAccount?> saveWithdrawAccount({
    required String realName,
    required String accountNo,
    required String paymentQrCode,
  }) async {
    try {
      final data = await _dio.apiPost(
        ApiEndpoints.withdrawAccount,
        data: {
          'real_name': realName,
          'account_no': accountNo,
          'payment_qr_code': paymentQrCode,
        },
      );
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) return null;
      return WithdrawAccount.fromJson(respData);
    } catch (e) {
      AppLogger.debug('wallet.saveWithdrawAccount error: $e');
      return null;
    }
  }

  Future<String?> uploadWithdrawQrCode({
    required List<int> bytes,
    required String filename,
  }) async {
    try {
      final prepared = await ImageUploadPreprocessor.instance.prepareImage(
        bytes: bytes,
        filename: filename,
        scene: ImageUploadScene.avatar,
      );
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          prepared.bytes,
          filename: prepared.filename,
        ),
      });
      final resp = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.withdrawUploadQrCode,
        data: formData,
      );
      final data = resp.data ?? {};
      if ((data['code'] as int?) != 200) {
        return null;
      }
      final url = (data['data'] as Map<String, dynamic>?)?['url'] as String?;
      return (url == null || url.trim().isEmpty) ? null : url.trim();
    } on ImageUploadPreprocessException catch (e) {
      AppLogger.debug(
        'wallet.uploadWithdrawQrCode preprocess error: ${e.message}',
      );
      return null;
    } on ApiException catch (e) {
      AppLogger.debug('wallet.uploadWithdrawQrCode ApiException: ${e.message}');
      return null;
    } catch (e) {
      AppLogger.debug('wallet.uploadWithdrawQrCode error: $e');
      return null;
    }
  }

  /// 刷新全部
  Future<void> refreshAll() async {
    await Future.wait([fetchBalance(), fetchTransactions()]);
  }
}

/// 钱包 Provider
final walletProvider = StateNotifierProvider<WalletNotifier, WalletState>((
  ref,
) {
  return WalletNotifier(DioClient.instance, ref);
});
