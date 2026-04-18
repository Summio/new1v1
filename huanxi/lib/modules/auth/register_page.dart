import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:huanxi/core/utils/app_toast.dart';
import '../../app/routes/app_router.dart';
import '../../core/network/dio_client.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/storage/storage.dart';
import '../../app/theme/app_theme.dart';
import '../../app/providers/auth_provider.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});
  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    if (phone.isEmpty) {
      AppToast.show(context, '请输入手机号');
      return;
    }
    if (phone.length != 11) {
      AppToast.show(context, '手机号格式不正确');
      return;
    }
    if (password.isEmpty) {
      AppToast.show(context, '请输入密码');
      return;
    }
    if (password.length < 8) {
      AppToast.show(context, '密码长度至少8位');
      return;
    }
    if (password != confirmPassword) {
      AppToast.show(context, '两次密码不一致');
      return;
    }
    setState(() {
      _isLoading = true;
    });

    final router = GoRouter.of(context);
    final notifier = ref.read(authProvider.notifier);

    try {
      final data = await DioClient.instance.apiPost(
        ApiEndpoints.appRegister,
        data: {'phone': phone, 'password': password, 'gender': 'secret'},
      );
      if (!mounted) return;

      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) {
        AppToast.show(context, '注册失败');
        return;
      }

      final token = respData['token'] as String?;
      final userId = respData['user_id'] as int?;
      if (token != null) {
        await StorageService.saveToken(token);
        if (userId != null) {
          await StorageService.saveUserId(userId);
        }
        notifier.setLoggedInAfterRegister(userId: userId!);
        router.go(AppRoutes.index);
      } else {
        router.go(AppRoutes.login);
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                ShaderMask(
                  shaderCallback: (bounds) =>
                      AppTheme.primaryGradient.createShader(bounds),
                  child: const Text(
                    '注册账号',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '填写以下信息完成注册',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 11,
                  decoration: const InputDecoration(
                    labelText: '手机号',
                    hintText: '请输入手机号',
                    prefixIcon: Icon(
                      Icons.phone_outlined,
                      color: AppTheme.textHint,
                    ),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密码',
                    hintText: '请输入密码（至少8位，含字母和数字）',
                    prefixIcon: Icon(
                      Icons.lock_outlined,
                      color: AppTheme.textHint,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '确认密码',
                    hintText: '请再次输入密码',
                    prefixIcon: Icon(
                      Icons.lock_outlined,
                      color: AppTheme.textHint,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: AppTheme.elevatedShadow,
                  ),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text(
                            '注册',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: TextButton(
                    onPressed: () => context.pop(),
                    child: const Text(
                      '已有账号？去登录',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
