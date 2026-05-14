import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/auth_provider.dart';
import '../../app/providers/wallet_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/app_toast.dart';

class WithdrawPage extends ConsumerStatefulWidget {
  const WithdrawPage({super.key});

  @override
  ConsumerState<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends ConsumerState<WithdrawPage> {
  int _selectedIndex = 0;
  bool _isLoadingPackages = true;
  bool _isLoadingAccount = true;
  bool _isSubmitting = false;
  String? _loadError;
  List<Map<String, dynamic>> _packages = [];
  WithdrawAccount _account = const WithdrawAccount();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadWithdrawConfig(), _loadAccount()]);
  }

  Future<void> _loadWithdrawConfig() async {
    setState(() {
      _isLoadingPackages = true;
      _loadError = null;
    });
    try {
      final data = await DioClient.instance.apiGet(ApiEndpoints.appBootstrap);
      final payload = data['data'];
      if (payload is! Map<String, dynamic>) {
        throw Exception('配置数据格式错误');
      }
      final packageList = payload['withdraw_packages'];
      if (packageList is! List || packageList.isEmpty) {
        throw Exception('暂无可用提现套餐');
      }
      final parsed = <Map<String, dynamic>>[];
      for (final item in packageList) {
        if (item is! Map<String, dynamic>) continue;
        final diamonds = _toInt(item['diamonds']);
        final amount = _toInt(item['amount']);
        if (diamonds <= 0 || amount <= 0) continue;
        parsed.add({
          'diamonds': diamonds,
          'amount': amount,
          'tag': item['tag']?.toString(),
          'tag_color': item['tag_color']?.toString(),
        });
      }
      if (parsed.isEmpty) {
        throw Exception('提现套餐配置无效');
      }
      if (!mounted) return;
      setState(() {
        _packages = parsed;
        if (_selectedIndex >= _packages.length) {
          _selectedIndex = 0;
        }
        _isLoadingPackages = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString().replaceFirst('Exception: ', '');
        _packages = [];
        _isLoadingPackages = false;
      });
    }
  }

  Future<void> _loadAccount() async {
    setState(() => _isLoadingAccount = true);
    final account = await ref
        .read(walletProvider.notifier)
        .fetchWithdrawAccount();
    if (!mounted) return;
    setState(() {
      _account = account ?? const WithdrawAccount();
      _isLoadingAccount = false;
    });
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  Color _parseColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) {
      return const Color(0xFFFF5722);
    }
    try {
      final hex = colorStr.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFFFF5722);
    }
  }

  Future<void> _editAccount() async {
    if (_account.isPending) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('提现账户待审核中，请勿重复提交')),
      );
      return;
    }
    final account = await context.push<WithdrawAccount>(
      AppRoutes.withdrawAccount,
      extra: _account,
    );
    if (account == null || !mounted) return;
    setState(() => _account = account);
    AppToast.showSnackBar(context, const SnackBar(content: Text('提现账户已提交审核')));
  }

  Future<void> _submitWithdraw() async {
    if (_isSubmitting || _packages.isEmpty) return;
    if (!_account.isComplete) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('请先填写提现账户')),
      );
      await _editAccount();
      return;
    }
    if (!_account.canWithdraw) {
      final message = _account.isPending
          ? '账户审核中，通过后才能提现'
          : _account.isRejected
          ? '账户审核未通过，请修改后重新提交'
          : '请先提交并通过提现账户审核';
      AppToast.showSnackBar(context, SnackBar(content: Text(message)));
      if (_account.isRejected) {
        await _editAccount();
      }
      return;
    }
    final pkg = _packages[_selectedIndex];
    final diamonds = _toInt(pkg['diamonds']);
    final available = ref.read(authProvider).diamonds;
    if (diamonds > available) {
      AppToast.showSnackBar(context, const SnackBar(content: Text('可提现余额不足')));
      return;
    }

    setState(() => _isSubmitting = true);
    final result = await ref
        .read(walletProvider.notifier)
        .withdraw(amount: diamonds);
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (result == null) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('提现申请失败，请稍后重试')),
      );
      return;
    }
    AppToast.showSnackBar(
      context,
      SnackBar(content: Text(result.msg.isEmpty ? '提现申请已提交' : result.msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final tokenNames = ref.watch(tokenNamesProvider);
    final diamondName = tokenNames.diamondName;

    if (!_isLoadingPackages && (_loadError != null || _packages.isEmpty)) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: _appBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  _loadError ?? '暂无可用提现套餐',
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadWithdrawConfig,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新加载'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: _appBar(),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.account_balance_wallet_outlined,
                          color: AppTheme.secondaryDark,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$diamondName余额: ${authState.diamonds.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.secondaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '选择提现套餐',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (_isLoadingPackages)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 1.1,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemCount: _packages.length,
                      itemBuilder: (context, index) =>
                          _buildPackageTile(index, diamondName),
                    ),
                  const SizedBox(height: 24),
                  const Text(
                    '提现账户',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildAccountCard(),
                ],
              ),
            ),
          ),
          if (!_isLoadingPackages && _packages.isNotEmpty) _buildSubmitBar(),
        ],
      ),
    );
  }

  AppBar _appBar() {
    return AppBar(
      backgroundColor: AppTheme.surfaceColor,
      title: const Text('钻石提现'),
      actions: [
        TextButton(
          onPressed: () => context.push(AppRoutes.diamondTransactions),
          child: const Text('明细'),
        ),
      ],
    );
  }

  Widget _buildPackageTile(int index, String diamondName) {
    final pkg = _packages[index];
    final isSelected = index == _selectedIndex;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.secondaryColor.withValues(alpha: 0.08)
              : AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTheme.secondaryColor
                : const Color(0xFFF0F0F0),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? AppTheme.cardShadow : null,
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${pkg['diamonds']}$diamondName',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? AppTheme.secondaryDark
                          : AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '提现 ${(pkg['amount'] / 100).toStringAsFixed(2)}元',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (pkg['tag'] != null && pkg['tag'].toString().isNotEmpty)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: _parseColor(pkg['tag_color']?.toString()),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    pkg['tag'].toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCard() {
    final statusText = _account.isPending
        ? '账户审核中'
        : _account.isApproved
        ? '已通过'
        : _account.isRejected
        ? '账户审核未通过'
        : '';
    final statusColor = _account.isApproved
        ? const Color(0xFF34C759)
        : _account.isRejected
        ? const Color(0xFFFF3B30)
        : const Color(0xFFFF9500);
    return GestureDetector(
      onTap: _isLoadingAccount ? null : _editAccount,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.account_balance_outlined,
                color: AppTheme.secondaryDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _isLoadingAccount
                  ? const Text(
                      '加载中...',
                      style: TextStyle(color: AppTheme.textSecondary),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _account.isComplete ? _account.realName : '填写提现账户',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (statusText.isNotEmpty) ...[
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 12,
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          _account.isComplete
                              ? '支付宝 ${_account.accountNo}'
                              : '真实姓名、支付宝账号、收款码',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textHint),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitBar() {
    final pkg = _packages[_selectedIndex];
    final disabled = _isSubmitting || _account.isPending;
    final label = _account.isPending
        ? '账户审核中'
        : _account.isRejected
        ? '修改账户后提现'
        : '提交提现 ￥${(pkg['amount'] / 100).toStringAsFixed(2)}';
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        height: 56,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(28),
            boxShadow: AppTheme.elevatedShadow,
          ),
          child: ElevatedButton(
            onPressed: disabled ? null : _submitWithdraw,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
