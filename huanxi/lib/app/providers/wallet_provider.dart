import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/utils/app_logger.dart';
import '../../app/providers/auth_provider.dart';

/// 交易记录类型
enum TransactionType { all, income, expense }

/// 单条交易记录
class TransactionRecord {
  final String id;
  final String type;
  final String title;
  final int amount;
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
    int parseInt(dynamic value, {int fallback = 0}) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value.trim()) ?? fallback;
      return fallback;
    }

    return TransactionRecord(
      id: (json['id'] ?? '').toString(),
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      amount: parseInt(json['amount']),
      isIncome: json['is_income'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

/// 钱包状态
class WalletState {
  final int coins;
  final int diamonds;
  final int frozenDiamonds;
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
    int? coins,
    int? diamonds,
    int? frozenDiamonds,
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
  final int diamonds;
  final int frozenDiamonds;
  final String msg;

  const WithdrawResult({
    required this.diamonds,
    required this.frozenDiamonds,
    required this.msg,
  });

  factory WithdrawResult.fromJson(Map<String, dynamic> json) {
    return WithdrawResult(
      diamonds: json['diamonds'] as int? ?? 0,
      frozenDiamonds: json['frozen_diamonds'] as int? ?? 0,
      msg: json['msg'] as String? ?? '',
    );
  }
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
        coins: respData['coins'] as int? ?? 0,
        diamonds: respData['diamonds'] as int? ?? 0,
        frozenDiamonds: respData['frozen_diamonds'] as int? ?? 0,
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
  Future<WithdrawResult?> withdraw({
    required int amount,
    required String bankName,
    required String accountNo,
    required String realName,
  }) async {
    try {
      final data = await _dio.apiPost(
        ApiEndpoints.withdrawApply,
        data: {
          'amount': amount,
          'bank_name': bankName,
          'account_no': accountNo,
          'real_name': realName,
        },
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
