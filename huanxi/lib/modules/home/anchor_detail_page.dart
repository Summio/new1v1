import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../app/providers/anchor_provider.dart';

/// 主播详情页 (Momo 风格)
class AnchorDetailPage extends ConsumerWidget {
  final AnchorInfo anchor;

  const AnchorDetailPage({super.key, required this.anchor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 头部大图
            Hero(
              tag: 'anchor_avatar_${anchor.userId}',
              child: Container(
                height: MediaQuery.of(context).size.width * 1.2,
                width: double.infinity,
                decoration: BoxDecoration(
                  image: anchor.avatar != null && anchor.avatar!.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(anchor.avatar!),
                          fit: BoxFit.cover,
                        )
                      : null,
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                ),
                child: anchor.avatar == null || anchor.avatar!.isEmpty
                    ? const Icon(Icons.person, size: 100, color: AppTheme.primaryColor)
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.3),
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.5),
                            ],
                            stops: const [0.0, 0.3, 0.7, 1.0],
                          ),
                        ),
                      ),
              ),
            ),

            // 信息区域
            Transform.translate(
              offset: const Offset(0, -30),
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 名字与状态
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                anchor.username ?? '主播',
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _buildTag(
                                    icon: Icons.female,
                                    label: '23', // 模拟年龄
                                    color: const Color(0xFFFF69B4),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildTag(
                                    icon: Icons.location_on,
                                    label: '1.2km', // 模拟距离
                                    color: AppTheme.textHint,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: (anchor.isOnline ?? false)
                                ? AppTheme.onlineGreen.withValues(alpha: 0.1)
                                : AppTheme.offlineGray.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: (anchor.isOnline ?? false)
                                      ? AppTheme.onlineGreen
                                      : AppTheme.offlineGray,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                (anchor.isOnline ?? false) ? '在线' : '离线',
                                style: TextStyle(
                                  color: (anchor.isOnline ?? false)
                                      ? AppTheme.onlineGreen
                                      : AppTheme.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    const Divider(color: AppTheme.dividerColor),
                    const SizedBox(height: 24),

                    // 关于我
                    const Text(
                      '关于我',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      anchor.anchorIntro ?? '这个主播很懒，还没有填写自我介绍哦~',
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppTheme.textSecondary,
                        height: 1.6,
                      ),
                    ),

                    const SizedBox(height: 32),
                    
                    // 礼物/魅力值 (模拟)
                    const Text(
                      '魅力与礼物',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(5, (index) => _buildGiftItem(index)),
                      ),
                    ),
                    
                    const SizedBox(height: 100), // 留出底部操作栏的空间
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              // 聊天按钮
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: () => context.push('${AppRoutes.im}/${anchor.userId}'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: AppTheme.dividerColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 20, color: AppTheme.textPrimary),
                      SizedBox(width: 8),
                      Text('聊一聊', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // 视频通话按钮
              Expanded(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: AppTheme.elevatedShadow,
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      context.push('${AppRoutes.callRoom}?roomId=room_${anchor.userId}&anchorId=${anchor.userId}');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.videocam, size: 22, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          '立即通话 (${anchor.callPrice?.toStringAsFixed(0) ?? '0'}/分)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGiftItem(int index) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.card_giftcard, color: AppTheme.primaryColor.withValues(alpha: 0.5)),
    );
  }
}
