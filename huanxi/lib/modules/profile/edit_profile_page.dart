import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/theme/app_theme.dart';

/// 编辑资料页
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  late TextEditingController _nicknameController;
  late TextEditingController _bioController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final authState = ref.read(authProvider);
    _nicknameController = TextEditingController(text: authState.username ?? '');
    _bioController = TextEditingController();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nicknameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('昵称不能为空')),
      );
      return;
    }

    setState(() => _isSaving = true);

    // TODO: 调用更新用户资料 API
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('资料已保存')),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑资料'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 头像
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                      backgroundImage: authState.avatar != null
                          ? NetworkImage(authState.avatar!)
                          : null,
                      child: authState.avatar == null
                          ? const Icon(Icons.person, size: 50, color: AppTheme.primaryColor)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('更换头像功能开发中')),
                        );
                      },
                      icon: const Icon(Icons.camera_alt_outlined, size: 18),
                      label: const Text('更换头像'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 昵称
              TextField(
                controller: _nicknameController,
                decoration: const InputDecoration(
                  labelText: '昵称',
                  hintText: '请输入昵称',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                maxLength: 20,
              ),

              const SizedBox(height: 16),

              // 个人简介
              TextField(
                controller: _bioController,
                decoration: const InputDecoration(
                  labelText: '个人简介',
                  hintText: '介绍一下自己吧',
                  prefixIcon: Icon(Icons.edit_note),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                maxLength: 100,
              ),

              const SizedBox(height: 24),

              // 其他信息（只读展示）
              _buildInfoTile('用户ID', authState.userId?.toString() ?? '-'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          const Spacer(),
          Text(value, style: const TextStyle(color: AppTheme.textHint, fontSize: 14)),
        ],
      ),
    );
  }
}
