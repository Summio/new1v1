import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/moment_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/app_toast.dart';
import '../../services/moment_service.dart';
import '../../app/routes/app_router.dart';
import 'moment_list_view.dart';

/// 我的动态列表页面
class MyMomentsPage extends ConsumerStatefulWidget {
  const MyMomentsPage({super.key});

  @override
  ConsumerState<MyMomentsPage> createState() => _MyMomentsPageState();
}

class _MyMomentsPageState extends ConsumerState<MyMomentsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(myMomentsProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myMomentsProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(AppRoutes.publishMoment),
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('我的动态'),
        centerTitle: true,
      ),
      body: MomentListView(
        moments: state.moments,
        isLoading: state.isLoading,
        isLoadingMore: state.isLoadingMore,
        hasMore: state.hasMore,
        error: state.error,
        onRefresh: () => ref.read(myMomentsProvider.notifier).load(),
        onLoadMore: () => ref.read(myMomentsProvider.notifier).loadMore(),
        onDelete: (moment) => _deleteMoment(moment),
      ),
    );
  }

  Future<void> _deleteMoment(Moment moment) async {
    final success = await ref.read(myMomentsProvider.notifier).deleteMoment(moment.id);
    if (success) {
      ref.read(momentFeedProvider.notifier).removeMoment(moment.id);
      if (mounted) {
        AppToast.show(context, '删除成功');
      }
    } else {
      if (mounted) {
        AppToast.show(context, '删除失败');
      }
    }
  }
}
