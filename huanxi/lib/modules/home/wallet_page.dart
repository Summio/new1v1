import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_theme.dart';
import '../../app/routes/app_router.dart';
import '../../app/providers/wallet_provider.dart';
import '../../app/providers/auth_provider.dart';

/// 钱包页面
/// 显示余额 + 账单明细
class WalletPage extends ConsumerStatefulWidget {
  const WalletPage({super.key});

  @override
  ConsumerState<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends ConsumerState<WalletPage> {
  int _selectedFilter = 0; // 0=all, 1=income, 2=expense

  String _formatAmount(double value) => value.toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    // 首次加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(walletProvider.notifier).refreshAll();
    });
  }

  void _onFilterChanged(int index) {
    setState(() => _selectedFilter = index);
    final type = index == 1
        ? TransactionType.income
        : index == 2
        ? TransactionType.expense
        : TransactionType.all;
    ref.read(walletProvider.notifier).fetchTransactions(type: type);
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletProvider);
    final tokenNames = ref.watch(tokenNamesProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('我的钱包'),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Column(
        children: [
          // ========== 余额卡片 ==========
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppTheme.elevatedShadow,
            ),
            child: Column(
              children: [
                const Text(
                  '我的余额',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _formatAmount(walletState.coins),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tokenNames.coinName,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Container(width: 1, height: 28, color: Colors.white30),
                    const SizedBox(width: 24),
                    Text(
                      _formatAmount(walletState.diamonds),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tokenNames.diamondName,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                if (walletState.frozenDiamonds > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '冻结中 ${_formatAmount(walletState.frozenDiamonds)}${tokenNames.diamondName}',
                    style: const TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.add_circle_outline,
                        label: '充值',
                        onTap: () => context.push(AppRoutes.recharge),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.account_balance_wallet_outlined,
                        label: '提现',
                        onTap: () => context.push(AppRoutes.withdraw),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ========== 账单明细 ==========
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  '账单明细',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '共 ${walletState.total} 条',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 筛选标签
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _FilterChip(
                  label: '全部',
                  isSelected: _selectedFilter == 0,
                  onTap: () => _onFilterChanged(0),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: '收入',
                  isSelected: _selectedFilter == 1,
                  onTap: () => _onFilterChanged(1),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: '支出',
                  isSelected: _selectedFilter == 2,
                  onTap: () => _onFilterChanged(2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 交易列表
          Expanded(
            child: _TransactionList(
              walletState: walletState,
              onLoadMore: () => ref.read(walletProvider.notifier).loadMore(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
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

class _TransactionList extends StatelessWidget {
  final WalletState walletState;
  final VoidCallback onLoadMore;

  const _TransactionList({required this.walletState, required this.onLoadMore});

  IconData _iconForType(String type) {
    switch (type) {
      case 'recharge':
        return Icons.account_balance;
      case 'call':
        return Icons.phone;
      case 'gift':
        return Icons.card_giftcard;
      case 'withdraw':
        return Icons.payments_outlined;
      default:
        return Icons.receipt_long;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'recharge':
        return const Color(0xFF4CAF50);
      case 'call':
        return const Color(0xFFFF7043);
      case 'gift':
        return const Color(0xFFFF4081);
      case 'withdraw':
        return const Color(0xFF7E57C2);
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (walletState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (walletState.transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 48, color: AppTheme.textHint),
            const SizedBox(height: 12),
            const Text(
              '暂无账单记录',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.extentAfter < 100 &&
            walletState.hasMore &&
            !walletState.isLoadingMore) {
          onLoadMore();
        }
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount:
            walletState.transactions.length +
            (walletState.isLoadingMore ? 1 : 0),
        separatorBuilder: (context, index) =>
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
        itemBuilder: (context, index) {
          if (index >= walletState.transactions.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }

          final record = walletState.transactions[index];
          final amountColor = record.isIncome
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
                    color: _colorForType(record.type).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _iconForType(record.type),
                    color: _colorForType(record.type),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        record.createdAt,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${record.isIncome ? '+' : '-'}${record.amount.toStringAsFixed(2)}',
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
    );
  }
}
