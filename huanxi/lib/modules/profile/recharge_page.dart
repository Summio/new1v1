import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_theme.dart';
import '../../app/providers/auth_provider.dart';

/// 充值页面
/// 显示充值套餐 + 支付方式选择
class RechargePage extends ConsumerStatefulWidget {
  const RechargePage({super.key});

  @override
  ConsumerState<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends ConsumerState<RechargePage> {
  int _selectedIndex = 0;
  final String coinName = '金币'; // default, overridden by tokenNamesProvider

  // 充值套餐
  final List<Map<String, dynamic>> _packages = [
    {'amount': 6, 'coins': 60, 'label': '6元', 'tag': '尝鲜'},
    {'amount': 30, 'coins': 300, 'label': '30元', 'tag': '推荐'},
    {'amount': 68, 'coins': 700, 'label': '68元', 'tag': '特惠'},
    {'amount': 128, 'coins': 1350, 'label': '128元', 'tag': '超值'},
    {'amount': 328, 'coins': 3500, 'label': '328元', 'tag': '豪礼'},
    {'amount': 648, 'coins': 7000, 'label': '648元', 'tag': '至尊'},
  ];

  int _payMethod = 0; // 0=支付宝 1=微信

  Future<void> _submitRecharge() async {
    final pkg = _packages[_selectedIndex];
    // TODO: 调用充值创建 API
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在唤起支付：${pkg['label']}...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokenNames = ref.watch(tokenNamesProvider);
    final dynamicCoinName = tokenNames.coinName;
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('我的钱包'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 充值说明 - 薄荷绿
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: AppTheme.secondaryDark, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '1元 = 10$dynamicCoinName，$dynamicCoinName用于拨打主播电话',
                            style: TextStyle(fontSize: 13, color: AppTheme.secondaryDark),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 充值套餐
                  const Text(
                    '选择充值金额',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                                ? AppTheme.secondaryColor.withValues(alpha: 0.08)
                                : AppTheme.surfaceColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? AppTheme.secondaryColor : const Color(0xFFF0F0F0),
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
                                      pkg['label'],
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
                                      gradient: pkg['tag'] == '推荐'
                                          ? AppTheme.primaryGradient
                                          : const LinearGradient(
                                              colors: [Color(0xFFFFB74D), Color(0xFFFF9800)],
                                            ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      pkg['tag'],
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

                  // 支付方式
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

          // 底部确认按钮 - 渐变
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
                onPressed: _submitRecharge,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                child: Text(
                  '立即支付 ¥${_packages[_selectedIndex]['amount']}',
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
            Icon(icon, color: isSelected ? AppTheme.secondaryDark : AppTheme.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppTheme.secondaryDark : AppTheme.textPrimary,
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
