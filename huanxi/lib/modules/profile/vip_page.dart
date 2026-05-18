import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/auth_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/vip_badge.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/utils/app_toast.dart';

class VipPage extends ConsumerStatefulWidget {
  const VipPage({super.key});

  @override
  ConsumerState<VipPage> createState() => _VipPageState();
}

class _VipPageState extends ConsumerState<VipPage> {
  int _selectedIndex = 0;
  int _payMethod = 0;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appInitProvider.notifier).init();
      ref.read(authProvider.notifier).fetchUserInfo();
    });
  }

  Future<void> _submitVipOrder(List<VipPackage> packages) async {
    if (_isSubmitting || packages.isEmpty) return;
    setState(() => _isSubmitting = true);
    final payChannel = _payMethod == 0 ? 'alipay' : 'wx';
    try {
      final data = await DioClient.instance.apiPost(
        ApiEndpoints.vipOrderCreate,
        data: {'package_index': _selectedIndex, 'pay_channel': payChannel},
      );
      final msg = data['msg']?.toString() ?? '订单已创建，请继续完成支付';
      if (!mounted) return;
      AppToast.showSnackBar(context, SnackBar(content: Text(msg)));
      await ref.read(authProvider.notifier).fetchUserInfo();
    } catch (_) {
      if (!mounted) return;
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('VIP订单创建失败，请稍后重试')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final initState = ref.watch(appInitProvider);
    final packages = initState.vipPackages;
    if (_selectedIndex >= packages.length) {
      _selectedIndex = 0;
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('VIP会员'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _VipStatusCard(authState: authState),
                  const SizedBox(height: 24),
                  const Text(
                    '选择会员套餐',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (initState.isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (packages.isEmpty)
                    const _EmptyPackages()
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 1.45,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemCount: packages.length,
                      itemBuilder: (context, index) {
                        final pkg = packages[index];
                        final isSelected = index == _selectedIndex;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedIndex = index),
                          child: _VipPackageCard(
                            package: pkg,
                            isSelected: isSelected,
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
                    icon: Icons.account_balance_wallet_outlined,
                    title: '支付宝',
                    isSelected: _payMethod == 0,
                    onTap: () => setState(() => _payMethod = 0),
                  ),
                  const SizedBox(height: 8),
                  _PayMethodTile(
                    icon: Icons.payment_outlined,
                    title: '微信支付',
                    isSelected: _payMethod == 1,
                    onTap: () => setState(() => _payMethod = 1),
                  ),
                ],
              ),
            ),
          ),
          if (packages.isNotEmpty)
            Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).padding.bottom + 16,
              ),
              color: AppTheme.surfaceColor,
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => _submitVipOrder(packages),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD79A2B),
                    foregroundColor: const Color(0xFF3F2600),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          '立即支付 ¥${packages[_selectedIndex].amountYuan}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
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

class _VipStatusCard extends StatelessWidget {
  final AuthState authState;

  const _VipStatusCard({required this.authState});

  @override
  Widget build(BuildContext context) {
    final expiresAt = authState.vipExpiresAt?.trim();
    final subtitle = authState.isVip
        ? '有效期至 ${_formatVipExpiresAt(expiresAt)}'
        : '开通后私信文字消息全免费';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFE8A3), Color(0xFFD79A2B)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          const VipBadge(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authState.isVip ? 'VIP会员已开通' : '开通VIP会员',
                  style: const TextStyle(
                    color: Color(0xFF3F2600),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF6F4A00),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatVipExpiresAt(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final normalized = raw.replaceFirst('T', ' ');
    return normalized.length > 16 ? normalized.substring(0, 16) : normalized;
  }
}

class _VipPackageCard extends StatelessWidget {
  final VipPackage package;
  final bool isSelected;

  const _VipPackageCard({required this.package, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFFFF7DD) : AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? const Color(0xFFD79A2B) : const Color(0xFFF0F0F0),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected ? AppTheme.cardShadow : null,
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                package.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${package.durationDays}天',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '¥${package.amountYuan}',
                style: const TextStyle(
                  color: Color(0xFFD79A2B),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (package.tag != null)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _parseColor(package.tagColor),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  package.tag!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _parseColor(String? raw) {
    final value = raw?.replaceFirst('#', '').trim();
    if (value == null || value.length != 6) return const Color(0xFFD79A2B);
    try {
      return Color(int.parse('FF$value', radix: 16));
    } catch (_) {
      return const Color(0xFFD79A2B);
    }
  }
}

class _EmptyPackages extends StatelessWidget {
  const _EmptyPackages();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text(
        '暂无可购买套餐',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
      ),
    );
  }
}

class _PayMethodTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _PayMethodTile({
    required this.icon,
    required this.title,
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
            color: isSelected ? const Color(0xFFD79A2B) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? const Color(0xFFD79A2B)
                  : AppTheme.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected ? const Color(0xFFD79A2B) : AppTheme.textHint,
            ),
          ],
        ),
      ),
    );
  }
}
