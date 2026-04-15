import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../app/theme/app_theme.dart';

class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});
  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final oldPwd = _oldPasswordController.text;
    final newPwd = _newPasswordController.text;
    final confirmPwd = _confirmPasswordController.text;
    if (oldPwd.isEmpty || newPwd.isEmpty || confirmPwd.isEmpty) { setState(() { _error = '请填写完整'; _success = null; }); return; }
    if (newPwd.length < 6) { setState(() { _error = '密码长度至少6位'; _success = null; }); return; }
    if (newPwd != confirmPwd) { setState(() { _error = '两次密码不一致'; _success = null; }); return; }
    setState(() { _error = null; _success = null; _isLoading = true; });
    try {
      await DioClient.instance.apiPost(ApiEndpoints.changePassword, data: {'old_password': oldPwd, 'new_password': newPwd});
      if (mounted) { setState(() { _isLoading = false; _success = '密码修改成功'; }); await Future.delayed(const Duration(seconds: 1)); if (mounted) context.pop(); }
    } catch (e) { if (mounted) setState(() { _isLoading = false; _error = e.toString(); }); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(title: const Text('修改密码'), backgroundColor: AppTheme.surfaceColor, elevation: 0),
      body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppTheme.surfaceColor, borderRadius: BorderRadius.circular(16), boxShadow: AppTheme.cardShadow), child: Column(children: [
          TextField(controller: _oldPasswordController, obscureText: true, decoration: const InputDecoration(labelText: '旧密码', prefixIcon: Icon(Icons.lock_outline))),
          const SizedBox(height: 16),
          TextField(controller: _newPasswordController, obscureText: true, decoration: const InputDecoration(labelText: '新密码（至少6位）', prefixIcon: Icon(Icons.lock_outline))),
          const SizedBox(height: 16),
          TextField(controller: _confirmPasswordController, obscureText: true, decoration: const InputDecoration(labelText: '确认新密码', prefixIcon: Icon(Icons.lock_outline))),
          if (_error != null) ...[const SizedBox(height: 16), Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 14))],
          if (_success != null) ...[const SizedBox(height: 16), Text(_success!, style: const TextStyle(color: AppTheme.primaryColor, fontSize: 14))],
        ])),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, height: 52, child: ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
          child: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))) : const Text('确认修改', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        )),
      ])),
    );
  }
}
