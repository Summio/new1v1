import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/anchor_provider.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';

/// 主播详情页 (Momo 风格)
class AnchorDetailPage extends ConsumerStatefulWidget {
  final AnchorInfo anchor;

  const AnchorDetailPage({super.key, required this.anchor});

  @override
  ConsumerState<AnchorDetailPage> createState() => _AnchorDetailPageState();
}

class _AnchorDetailPageState extends ConsumerState<AnchorDetailPage> {
  bool _showExtendedContent = false;
  bool _isActionNavigating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _showExtendedContent = true);
    });
  }

  Future<void> _openIm({
    required bool isSelf,
    required AnchorInfo anchor,
  }) async {
    if (isSelf || _isActionNavigating) return;
    setState(() => _isActionNavigating = true);
    try {
      await context.push(
        '${AppRoutes.im}/${anchor.userId}',
        extra: {
          'peerNickname': anchor.username,
          'peerAvatarUrl': anchor.avatar,
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isActionNavigating = false);
      }
    }
  }

  Future<void> _openCall(AnchorInfo anchor) async {
    if (_isActionNavigating) return;
    setState(() => _isActionNavigating = true);
    try {
      final dialingRes = await DioClient.instance.apiPost(
        ApiEndpoints.dialing,
        data: {'anchor_id': anchor.id},
      );
      final dialingData = dialingRes['data'] as Map<String, dynamic>?;
      final callId = (dialingData?['call_id'] as num?)?.toInt();
      if (callId == null || callId <= 0) {
        throw const ApiException(code: 400, message: '呼叫创建失败，请稍后重试');
      }

      await context.push(
        '${AppRoutes.callRoom}?callId=$callId&anchorId=${anchor.userId}',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('通话启动失败，请稍后重试')),
      );
    } finally {
      if (mounted) {
        setState(() => _isActionNavigating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final anchor = widget.anchor;
    final myUserId = ref.watch(authProvider).userId;
    final isSelf = myUserId != null && myUserId == anchor.userId;
    final screenWidth = MediaQuery.of(context).size.width;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final rawHeaderCacheWidth = (screenWidth * devicePixelRatio).round();
    final headerCacheWidth = rawHeaderCacheWidth > 1080 ? 1080 : rawHeaderCacheWidth;
    final hasAvatar = anchor.avatar != null && anchor.avatar!.isNotEmpty;

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
            Hero(
              tag: 'anchor_avatar_${anchor.userId}',
              child: SizedBox(
                height: screenWidth * 1.2,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: AppTheme.primaryColor.withValues(alpha: 0.08)),
                    if (hasAvatar)
                      Image.network(
                        anchor.avatar!,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.low,
                        cacheWidth: headerCacheWidth,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return _buildHeaderPlaceholder();
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return _buildHeaderPlaceholder();
                        },
                      )
                    else
                      _buildHeaderPlaceholder(),
                    if (hasAvatar)
                      Container(
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
                  ],
                ),
              ),
            ),
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
                                    label: '23',
                                    color: const Color(0xFFFF69B4),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildTag(
                                    icon: Icons.location_on,
                                    label: '1.2km',
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
                    if (_showExtendedContent) ...[
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
                    ] else
                      _buildDeferredSkeleton(),
                    const SizedBox(height: 100),
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
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: isSelf || _isActionNavigating
                      ? null
                      : () => _openIm(isSelf: isSelf, anchor: anchor),
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
              Expanded(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: AppTheme.elevatedShadow,
                  ),
                  child: ElevatedButton(
                    onPressed: _isActionNavigating ? null : () => _openCall(anchor),
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

  Widget _buildHeaderPlaceholder() {
    return Container(
      color: const Color(0xFFEFEFF4),
      child: const Center(
        child: Icon(Icons.person, size: 100, color: AppTheme.primaryColor),
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

  Widget _buildDeferredSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 80,
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFFEFEFF4),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          height: 14,
          decoration: BoxDecoration(
            color: const Color(0xFFEFEFF4),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 220,
          height: 14,
          decoration: BoxDecoration(
            color: const Color(0xFFEFEFF4),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 32),
        Container(
          width: 110,
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFFEFEFF4),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: List.generate(
            4,
            (index) => Container(
              margin: const EdgeInsets.only(right: 12),
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFEFEFF4),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
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
