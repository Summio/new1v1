import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/providers/gift_provider.dart';
import '../../app/theme/app_theme.dart';

/// 礼物面板
/// 全屏底部弹窗，显示礼物列表，支持发送礼物
class GiftPanel extends ConsumerStatefulWidget {
  final String anchorId;
  final VoidCallback onClose;

  const GiftPanel({
    super.key,
    required this.anchorId,
    required this.onClose,
  });

  @override
  ConsumerState<GiftPanel> createState() => _GiftPanelState();
}

class _GiftPanelState extends ConsumerState<GiftPanel> {
  int _selectedIndex = 0;
  int _sendCount = 1;
  bool _isSending = false;

  // 本地图标映射（API iconUrl 加载失败时的兜底）
  static const Map<String, IconData> _iconMap = {
    'flower': Icons.local_florist,
    'love': Icons.favorite,
    'cake': Icons.cake,
    'wine': Icons.wine_bar,
    'diamond': Icons.diamond,
    'car': Icons.directions_car,
    'rocket': Icons.rocket,
    'castle': Icons.castle,
    'crown': Icons.workspace_premium,
  };

  @override
  void initState() {
    super.initState();
    // 初始化时获取礼物列表
    Future.microtask(() {
      ref.read(giftListProvider.notifier).fetchGifts();
    });
  }

  void _increment() => setState(() => _sendCount++);
  void _decrement() {
    if (_sendCount > 1) setState(() => _sendCount--);
  }

  Future<void> _sendGift() async {
    final giftState = ref.read(giftListProvider);
    if (giftState.gifts.isEmpty) return;

    final gift = giftState.gifts[_selectedIndex];
    final total = gift.price * _sendCount;

    setState(() => _isSending = true);

    final success = await ref.read(giftListProvider.notifier).sendGift(
          giftId: gift.id,
          anchorId: int.tryParse(widget.anchorId) ?? 0,
        );

    setState(() => _isSending = false);

    if (!mounted) return;

    if (success) {
      // 刷新余额
      ref.read(authProvider.notifier).refreshBalance();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已发送 ${_sendCount}x ${gift.name}，共 ¥${total.toStringAsFixed(0)}')),
      );
      widget.onClose();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('发送失败，请重试')),
      );
    }
  }

  IconData _getIcon(String? iconUrl, String fallback) {
    return _iconMap[fallback] ?? Icons.card_giftcard;
  }

  @override
  Widget build(BuildContext context) {
    final giftState = ref.watch(giftListProvider);
    final authState = ref.watch(authProvider);
    final tokenNames = ref.watch(tokenNamesProvider);
    final gifts = giftState.gifts;
    final selectedGift = gifts.isNotEmpty && _selectedIndex < gifts.length
        ? gifts[_selectedIndex]
        : null;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动条
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.secondaryColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 头部
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                const Text(
                  '发送礼物',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                if (authState.isLoggedIn)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${tokenNames.coinName}: ${authState.coins}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondaryDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),

          // 礼物网格
          SizedBox(
            height: 200,
            child: giftState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : giftState.error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(giftState.error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 12)),
                            TextButton(
                              onPressed: () => ref.read(giftListProvider.notifier).fetchGifts(),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : gifts.isEmpty
                        ? const Center(
                            child: Text(
                              '暂无可发送的礼物',
                              style: TextStyle(color: AppTheme.textHint),
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            scrollDirection: Axis.horizontal,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 1,
                            ),
                            itemCount: gifts.length,
                            itemBuilder: (context, index) {
                              final g = gifts[index];
                              final isSelected = index == _selectedIndex;
                              return GestureDetector(
                                onTap: () => setState(() => _selectedIndex = index),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.secondaryColor.withValues(alpha: 0.1)
                                        : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? AppTheme.secondaryColor : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      g.icon.isNotEmpty
                                          ? Image.network(
                                              g.icon,
                                              width: 28,
                                              height: 28,
                                              errorBuilder: (ctx, err, trace) => Icon(
                                                _getIcon(g.icon, 'gift'),
                                                color: isSelected
                                                    ? AppTheme.secondaryDark
                                                    : AppTheme.textSecondary,
                                                size: 28,
                                              ),
                                            )
                                          : Icon(
                                              Icons.card_giftcard,
                                              color: isSelected
                                                  ? AppTheme.secondaryDark
                                                  : AppTheme.textSecondary,
                                              size: 28,
                                            ),
                                      const SizedBox(height: 2),
                                      Text(
                                        g.name,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isSelected ? AppTheme.secondaryDark : AppTheme.textSecondary,
                                        ),
                                      ),
                                      Text(
                                        '¥${g.price.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isSelected ? AppTheme.secondaryDark : AppTheme.textHint,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),

          const Divider(height: 1),

          // 底部发送栏
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(context).padding.bottom + 12,
            ),
            child: Row(
              children: [
                // 数量选择
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.secondaryColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove, size: 18),
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        onPressed: _decrement,
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '$_sendCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 18),
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        onPressed: _increment,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // 快捷数量
                ...([1, 10, 66, 188]).map((n) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => setState(() => _sendCount = n),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _sendCount == n
                                ? AppTheme.secondaryColor.withValues(alpha: 0.1)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _sendCount == n ? AppTheme.secondaryColor : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            '${n}x',
                            style: TextStyle(
                              fontSize: 12,
                              color: _sendCount == n ? AppTheme.secondaryDark : AppTheme.textSecondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    )),

                const Spacer(),

                // 发送按钮 - 渐变
                Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: ElevatedButton(
                    onPressed: (_isSending || gifts.isEmpty || selectedGift == null)
                        ? null
                        : _sendGift,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            '发送 ¥${selectedGift != null ? (selectedGift.price * _sendCount).toStringAsFixed(0) : 0}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
