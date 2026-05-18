import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';

class CoinTransactionsPage extends ConsumerStatefulWidget {
  const CoinTransactionsPage({super.key});

  @override
  ConsumerState<CoinTransactionsPage> createState() =>
      _CoinTransactionsPageState();
}

class _CoinTransactionsPageState extends ConsumerState<CoinTransactionsPage> {
  final List<_CoinRecord> _records = <_CoinRecord>[];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  int _total = 0;
  int _filter = 0; // 0=all 1=income 2=expense

  String _formatAmount(double value) => value.toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    _fetchRecords(reset: true);
  }

  Future<void> _fetchRecords({required bool reset}) async {
    if (reset) {
      if (_isLoading) return;
      setState(() {
        _isLoading = true;
      });
    } else {
      if (_isLoadingMore || !_hasMore) return;
      setState(() {
        _isLoadingMore = true;
      });
    }

    final targetPage = reset ? 1 : (_page + 1);
    try {
      final data = await DioClient.instance.apiGet(
        ApiEndpoints.walletTransactions,
        params: {'type': 'coins', 'page': targetPage, 'page_size': 20},
      );
      final payload = data['data'] as Map<String, dynamic>?;
      final list = (payload?['records'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(_CoinRecord.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        if (reset) {
          _records
            ..clear()
            ..addAll(list);
        } else {
          _records.addAll(list);
        }
        _total = payload?['total'] as int? ?? 0;
        _hasMore = payload?['has_more'] as bool? ?? false;
        _page = targetPage;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('明细加载失败，请稍后重试')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  List<_CoinRecord> _filteredRecords() {
    if (_filter == 1) {
      return _records.where((record) => record.isIncome).toList();
    }
    if (_filter == 2) {
      return _records.where((record) => !record.isIncome).toList();
    }
    return _records;
  }

  @override
  Widget build(BuildContext context) {
    final tokenNames = ref.watch(tokenNamesProvider);
    final rows = _filteredRecords();
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        centerTitle: true,
        title: Text('${tokenNames.coinName}明细'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                const Text(
                  '账单记录',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '共 $_total 条',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                _FilterChip(
                  label: '全部',
                  isSelected: _filter == 0,
                  onTap: () => setState(() => _filter = 0),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: '收入',
                  isSelected: _filter == 1,
                  onTap: () => setState(() => _filter = 1),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: '支出',
                  isSelected: _filter == 2,
                  onTap: () => setState(() => _filter = 2),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _fetchRecords(reset: true),
              child: _isLoading
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(
                          height: 320,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ],
                    )
                  : rows.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(
                          height: 320,
                          child: Center(
                            child: Text(
                              '暂无金币账单记录',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollEndNotification &&
                            notification.metrics.extentAfter < 100 &&
                            _hasMore &&
                            !_isLoadingMore) {
                          _fetchRecords(reset: false);
                        }
                        return false;
                      },
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: rows.length + (_isLoadingMore ? 1 : 0),
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: Color(0xFFF0F0F0)),
                        itemBuilder: (context, index) {
                          if (index >= rows.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }
                          final row = rows[index];
                          final amountColor = row.isIncome
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFFF5252);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: _typeColor(
                                      row.type,
                                    ).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _typeIcon(row.type),
                                    color: _typeColor(row.type),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        row.title,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '对方：${row.counterpartyName.isEmpty ? '-' : row.counterpartyName}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        row.createdAt,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${row.isIncome ? '+' : '-'}${_formatAmount(row.amount)}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: amountColor,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'recharge':
        return Icons.account_balance;
      case 'call':
        return Icons.phone;
      case 'gift':
        return Icons.card_giftcard;
      default:
        return Icons.receipt_long;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'recharge':
        return const Color(0xFF4CAF50);
      case 'call':
        return const Color(0xFFFF7043);
      case 'gift':
        return const Color(0xFFFF4081);
      default:
        return AppTheme.textSecondary;
    }
  }
}

class _CoinRecord {
  final String id;
  final String type;
  final String title;
  final double amount;
  final bool isIncome;
  final String createdAt;
  final String counterpartyName;

  const _CoinRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.amount,
    required this.isIncome,
    required this.createdAt,
    required this.counterpartyName,
  });

  factory _CoinRecord.fromJson(Map<String, dynamic> json) {
    return _CoinRecord(
      id: (json['id'] ?? '').toString(),
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      isIncome: json['is_income'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? '',
      counterpartyName: json['counterparty_name'] as String? ?? '',
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.secondaryColor : AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTheme.secondaryColor
                : const Color(0xFFF0F0F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isSelected ? Colors.white : AppTheme.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
