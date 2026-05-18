import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/certified_user_provider.dart';
import '../../app/providers/user_search_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/status_view.dart';
import '../../app/widgets/vip_badge.dart';

class UserSearchPage extends ConsumerStatefulWidget {
  const UserSearchPage({super.key});

  @override
  ConsumerState<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends ConsumerState<UserSearchPage> {
  final TextEditingController _keywordController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      ref.read(userSearchProvider.notifier).loadMore();
    }
  }

  void _submitSearch() {
    FocusScope.of(context).unfocus();
    ref.read(userSearchProvider.notifier).search(_keywordController.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userSearchProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleSpacing: 0,
        title: TextField(
          controller: _keywordController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          keyboardType: TextInputType.text,
          onSubmitted: (_) => _submitSearch(),
          decoration: InputDecoration(
            hintText: '搜索昵称或用户ID',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _keywordController.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _keywordController.clear();
                      ref.read(userSearchProvider.notifier).search('');
                      setState(() {});
                    },
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          TextButton(onPressed: _submitSearch, child: const Text('搜索')),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(UserSearchState state) {
    if (!state.hasKeyword) {
      return StatusView.empty(message: '输入昵称或用户ID开始搜索');
    }
    if (state.isLoading && state.users.isEmpty) {
      return StatusView.loading(message: '搜索中...');
    }
    if (state.error != null && state.users.isEmpty) {
      return StatusView.error(
        message: state.error!,
        onRetry: () =>
            ref.read(userSearchProvider.notifier).search(state.keyword),
      );
    }
    if (state.users.isEmpty) {
      return StatusView.empty(message: '未找到相关用户');
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: state.users.length + (state.isLoading ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index >= state.users.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _UserSearchTile(user: state.users[index]);
      },
    );
  }
}

class _UserSearchTile extends StatelessWidget {
  final CertifiedUserInfo user;

  const _UserSearchTile({required this.user});

  @override
  Widget build(BuildContext context) {
    final name = user.username?.trim().isNotEmpty == true
        ? user.username!
        : '用户${user.userId}';
    return Material(
      color: AppTheme.surfaceColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push(AppRoutes.certifiedUserDetail, extra: user),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppTheme.placeholderColor,
                backgroundImage: user.avatar != null && user.avatar!.isNotEmpty
                    ? NetworkImage(user.avatar!)
                    : null,
                child: user.avatar == null || user.avatar!.isEmpty
                    ? const Icon(Icons.person, color: AppTheme.textSecondary)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (user.isVip) ...[
                          const SizedBox(width: 4),
                          const VipBadge(dense: true),
                        ],
                        const SizedBox(width: 6),
                        _UserTypeBadge(isCertifiedUser: user.isCertifiedUser),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'ID：${user.userId}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserTypeBadge extends StatelessWidget {
  final bool isCertifiedUser;

  const _UserTypeBadge({required this.isCertifiedUser});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isCertifiedUser
            ? AppTheme.primaryColor.withValues(alpha: 0.12)
            : AppTheme.textSecondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isCertifiedUser ? '认证用户' : '用户',
        style: TextStyle(
          color: isCertifiedUser
              ? AppTheme.primaryColor
              : AppTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
