import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_theme.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/routes/app_router.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import 'package:huanxi/core/utils/app_toast.dart';

/// 充值页面
/// 显示充值套餐 + 支付方式选择
class RechargePage extends ConsumerStatefulWidget {
  const RechargePage({super.key});

  @override
  ConsumerState<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends ConsumerState<RechargePage> {
  int _selectedIndex = 0;
  bool _isLoadingPackages = true;
  bool _isSubmitting = false;
  int _tokenRate = 10;
  String? _loadError;

  List<Map<String, dynamic>> _packages = [];

  int _payMethod = 0; // 0=支付宝 1=微信

  @override
  void initState() {
    super.initState();
    _loadRechargeConfig();
  }

  Future<void> _loadRechargeConfig() async {
    if (!mounted) return;
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

      final rateRaw = payload['token_rate'];
      final tokenRate = rateRaw is num ? rateRaw.toInt() : _tokenRate;
      final packageList = payload['recharge_packages'];

      if (packageList is! List || packageList.isEmpty) {
        throw Exception('暂无可用充值套餐');
      }

      final parsed = <Map<String, dynamic>>[];
      for (final item in packageList) {
        if (item is! Map<String, dynamic>) continue;
        final amount = _toInt(item['amount'] ?? item['money']);
        final coins = _toInt(item['coins'] ?? item['token_amount']);
        if (amount <= 0 || coins <= 0) continue;
        parsed.add({
          'amount': amount,
          'coins': coins,
          'tag': item['tag']?.toString(),
          'tag_color': item['tag_color']?.toString(),
        });
      }

      if (parsed.isEmpty) {
        throw Exception('充值套餐配置无效');
      }

      if (!mounted) return;
      setState(() {
        _tokenRate = tokenRate > 0 ? tokenRate : _tokenRate;
        _packages = parsed;
        if (_selectedIndex >= _packages.length) {
          _selectedIndex = 0;
        }
        _isLoadingPackages = false;
      });
    } catch (e) {
      debugPrint('recharge.loadConfig error: $e');
      if (!mounted) return;
      setState(() {
        _loadError = e.toString().replaceFirst('Exception: ', '');
        _packages = [];
        _isLoadingPackages = false;
      });
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  Color _parseColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) {
      return const Color(0xFFFF5722); // 默认颜色
    }
    try {
      // 移除 # 前缀
      final hex = colorStr.replaceFirst('#', '');
      // 解析为整数并添加完全不透明的 alpha 通道
      return Color(int.parse('FF$hex', radix: 16));
    } catch (e) {
      return const Color(0xFFFF5722); // 解析失败时使用默认颜色
    }
  }

  Future<void> _submitRecharge() async {
    if (_isSubmitting || _packages.isEmpty) return;
    setState(() => _isSubmitting = true);
    final pkg = _packages[_selectedIndex];
    final payChannel = _payMethod == 0 ? 'alipay' : 'wechat';
    try {
      final data = await DioClient.instance.apiPost(
        ApiEndpoints.rechargeCreate,
        data: {'amount': pkg['amount'], 'pay_channel': payChannel},
      );
      final msg = data['msg']?.toString() ?? '订单已创建，请继续完成支付';
      if (!mounted) return;
      AppToast.showSnackBar(context, SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('充值失败，请稍后重试')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokenNames = ref.watch(tokenNamesProvider);
    final dynamicCoinName = tokenNames.coinName;

    // 加载失败或无套餐时显示错误页面
    if (!_isLoadingPackages && (_loadError != null || _packages.isEmpty)) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          backgroundColor: AppTheme.surfaceColor,
          title: const Text('充值'),
        ),
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
                  _loadError ?? '暂无可用充值套餐',
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadRechargeConfig,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新加载'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('充值'),
        actions: [
          TextButton(
            onPressed: () => context.push(AppRoutes.coinTransactions),
            child: const Text('明细'),
          ),
        ],
      ),
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
                          Icons.info_outline,
                          color: AppTheme.secondaryDark,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '1元 = $_tokenRate$dynamicCoinName，$dynamicCoinName用于拨打认证用户电话',
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
                    '选择充值金额',
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
                      itemBuilder: (context, index) {
                        final pkg = _packages[index];
                        final isSelected = index == _selectedIndex;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedIndex = index),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.secondaryColor.withValues(
                                      alpha: 0.08,
                                    )
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
                                        '${(pkg['amount'] / 100).toStringAsFixed(2)}元',
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
                                        '${pkg['coins']}$dynamicCoinName',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (pkg['tag'] != null)
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
                                        pkg['tag']?.toString() ?? '',
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
                      },
                    ),
                  const SizedBox(height: 24),
                  const Text(
                    '选择支付方式',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _PayMethodTile(
                    icon: Icons.paypal,
                    title: '支付宝',
                    subtitle: '推荐',
                    isSelected: _payMethod == 0,
                    onTap: () => setState(() => _payMethod = 0),
                  ),
                  const SizedBox(height: 8),
                  _PayMethodTile(
                    icon: Icons.payment,
                    title: '微信支付',
                    subtitle: '',
                    isSelected: _payMethod == 1,
                    onTap: () => setState(() => _payMethod = 1),
                  ),
                ],
              ),
            ),
          ),
          if (!_isLoadingPackages && _packages.isNotEmpty)
            Container(
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
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: AppTheme.elevatedShadow,
                ),
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitRecharge,
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
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          '立即支付 ￥${(_packages[_selectedIndex]['amount'] / 100).toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PayMethodTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _PayMethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.cardShadow,
          border: Border.all(
            color: isSelected ? AppTheme.secondaryColor : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? AppTheme.secondaryDark
                  : AppTheme.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? AppTheme.secondaryDark
                      : AppTheme.textPrimary,
                ),
              ),
            ),
            if (subtitle.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.secondaryDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected ? AppTheme.secondaryDark : AppTheme.textHint,
            ),
          ],
        ),
      ),
    );
  }
}
