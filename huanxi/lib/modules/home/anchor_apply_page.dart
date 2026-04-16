import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';

/// 主播申请状态
enum AnchorApplyStatus { none, pending, approved, rejected }

/// 主播申请状态数据
class AnchorApplyState {
  final AnchorApplyStatus status;
  final String? rejectReason;
  final bool isLoading;

  const AnchorApplyState({
    this.status = AnchorApplyStatus.none,
    this.rejectReason,
    this.isLoading = false,
  });

  AnchorApplyState copyWith({
    AnchorApplyStatus? status,
    String? rejectReason,
    bool? isLoading,
  }) {
    return AnchorApplyState(
      status: status ?? this.status,
      rejectReason: rejectReason ?? this.rejectReason,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 主播申请 Provider
class AnchorApplyNotifier extends StateNotifier<AnchorApplyState> {
  final DioClient _dio;

  AnchorApplyNotifier(this._dio) : super(const AnchorApplyState());

  /// 查询申请状态
  Future<void> fetchStatus() async {
    state = state.copyWith(isLoading: true);
    try {
      final data = await _dio.apiGet(ApiEndpoints.anchorApplyStatus);
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) {
        state = state.copyWith(isLoading: false, status: AnchorApplyStatus.none);
        return;
      }

      final statusStr = respData['status'] as String? ?? 'none';
      state = state.copyWith(
        isLoading: false,
        status: _parseStatus(statusStr),
        rejectReason: respData['reject_reason'] as String?,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, status: AnchorApplyStatus.none);
    }
  }

  /// 提交申请
  Future<bool> apply({
    required String intro,
    required List<String> tags,
    required int callPrice,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final data = await _dio.apiPost(
        ApiEndpoints.anchorApply,
        data: {
          'intro': intro,
          'tags': tags,
          'call_price': callPrice,
        },
      );

      final code = data['code'] as int?;
      if (code == 200) {
        state = state.copyWith(isLoading: false, status: AnchorApplyStatus.pending);
        return true;
      } else {
        state = state.copyWith(isLoading: false);
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return false;
    }
  }

  AnchorApplyStatus _parseStatus(String status) {
    switch (status) {
      case 'pending':
        return AnchorApplyStatus.pending;
      case 'approved':
        return AnchorApplyStatus.approved;
      case 'rejected':
        return AnchorApplyStatus.rejected;
      default:
        return AnchorApplyStatus.none;
    }
  }

  /// 重置为可申请状态（驳回后点击"重新申请"）
  void resetToForm() {
    state = state.copyWith(status: AnchorApplyStatus.none, rejectReason: null);
  }
}

/// 主播申请 Provider
final anchorApplyProvider = StateNotifierProvider<AnchorApplyNotifier, AnchorApplyState>((ref) {
  return AnchorApplyNotifier(DioClient.instance);
});

/// 主播申请页
class AnchorApplyPage extends ConsumerStatefulWidget {
  const AnchorApplyPage({super.key});

  @override
  ConsumerState<AnchorApplyPage> createState() => _AnchorApplyPageState();
}

class _AnchorApplyPageState extends ConsumerState<AnchorApplyPage> {
  final _introController = TextEditingController();
  final _priceController = TextEditingController(text: '60');
  final _formKey = GlobalKey<FormState>();

  final List<String> _availableTags = ['情感咨询', '聊天陪伴', '游戏陪玩', '知识分享', '才艺展示', '心理咨询'];
  final List<String> _selectedTags = [];

  @override
  void initState() {
    super.initState();
    // 查询当前申请状态
    Future.microtask(() => ref.read(anchorApplyProvider.notifier).fetchStatus());
  }

  @override
  void dispose() {
    _introController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final applyState = ref.watch(anchorApplyProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('申请成为主播'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: applyState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(applyState),
    );
  }

  Widget _buildContent(AnchorApplyState state) {
    switch (state.status) {
      case AnchorApplyStatus.pending:
        return _buildPendingView();
      case AnchorApplyStatus.approved:
        return _buildApprovedView();
      case AnchorApplyStatus.rejected:
        return _buildRejectedView(state.rejectReason);
      case AnchorApplyStatus.none:
        return _buildApplyForm();
    }
  }

  Widget _buildPendingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hourglass_empty, size: 80, color: AppTheme.secondaryColor),
            const SizedBox(height: 24),
            const Text('申请已提交', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            const Text('请耐心等待审核，预计1-3个工作日', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => context.pop(),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12)),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApprovedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 80, color: Color(0xFF34C759)),
            const SizedBox(height: 24),
            const Text('审核通过', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            const Text('您已成为认证主播', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => context.pop(),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12)),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRejectedView(String? reason) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cancel, size: 80, color: AppTheme.errorColor),
            const SizedBox(height: 24),
            const Text('申请被拒绝', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            if (reason != null) ...[
              const SizedBox(height: 12),
              Text(reason, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                ref.read(anchorApplyProvider.notifier).resetToForm();
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12)),
              child: const Text('重新申请'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApplyForm() {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const Text('申请简介', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _introController,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: '介绍一下自己的擅长领域和优势...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入申请简介';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            const Text('擅长领域', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _availableTags.map((tag) {
                final isSelected = _selectedTags.contains(tag);
                return FilterChip(
                  label: Text(tag),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedTags.add(tag);
                      } else {
                        _selectedTags.remove(tag);
                      }
                    });
                  },
                  selectedColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                  checkmarkColor: AppTheme.primaryColor,
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const Text('通话价格 (分/分钟)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '10-1000',
                suffixText: '分/分钟',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入通话价格';
                }
                final price = int.tryParse(value);
                if (price == null || price < 10 || price > 1000) {
                  return '价格范围: 10-1000 分/分钟';
                }
                return null;
              },
            ),
            const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _handleSubmit,
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25))),
                  child: const Text('提交申请', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final price = int.tryParse(_priceController.text) ?? 60;
    final success = await ref.read(anchorApplyProvider.notifier).apply(
          intro: _introController.text.trim(),
          tags: _selectedTags,
          callPrice: price,
        );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('申请已提交'), backgroundColor: Color(0xFF34C759)),
      );
    }
  }
}
