import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers/auth_provider.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/constants/app_constants.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/storage.dart';
import '../../core/utils/media_url.dart';
import '../../core/utils/app_toast.dart';

class InitialProfilePage extends ConsumerStatefulWidget {
  const InitialProfilePage({super.key});

  @override
  ConsumerState<InitialProfilePage> createState() => _InitialProfilePageState();
}

class _InitialProfilePageState extends ConsumerState<InitialProfilePage> {
  String _gender = 'male';
  String _avatar = '';
  String _nickname = '';
  bool _loading = false;
  bool _submitting = false;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    setState(() => _loading = true);
    try {
      final data = await DioClient.instance.apiGet(
        ApiEndpoints.initialProfileOptions,
        params: {'gender': _gender},
      );
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) return;
      setState(() {
        _gender = (respData['gender'] as String?) ?? _gender;
        _avatar = (respData['selected_avatar'] as String?)?.trim() ?? '';
        _nickname = (respData['selected_nickname'] as String?)?.trim() ?? '';
      });
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _randomAvatar() async {
    if (_loading || _submitting || _loggingOut) return;
    try {
      final data = await DioClient.instance.apiPost(
        ApiEndpoints.initialProfileRandomAvatar,
        data: {'gender': _gender},
      );
      if (!mounted) return;
      final respData = data['data'] as Map<String, dynamic>?;
      final avatar = (respData?['avatar'] as String?)?.trim() ?? '';
      if (avatar.isEmpty) {
        AppToast.show(context, '当前头像池为空');
        return;
      }
      setState(() => _avatar = avatar);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  Future<void> _randomNickname() async {
    if (_loading || _submitting || _loggingOut) return;
    try {
      final data = await DioClient.instance.apiPost(
        ApiEndpoints.initialProfileRandomNickname,
        data: {'gender': _gender},
      );
      if (!mounted) return;
      final respData = data['data'] as Map<String, dynamic>?;
      final nickname = (respData?['nickname'] as String?)?.trim() ?? '';
      if (nickname.isEmpty) {
        AppToast.show(context, '当前昵称池为空');
        return;
      }
      setState(() => _nickname = nickname);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    }
  }

  Future<void> _handleGenderChange(String gender) async {
    if (gender == _gender || _loading || _submitting || _loggingOut) return;
    setState(() => _gender = gender);
    await _loadOptions();
  }

  Future<void> _complete() async {
    if (_submitting || _loggingOut) return;
    if (_avatar.isEmpty || _nickname.isEmpty) {
      AppToast.show(context, '请先选择头像和昵称');
      return;
    }
    setState(() => _submitting = true);
    try {
      final data = await DioClient.instance.apiPost(
        ApiEndpoints.initialProfileComplete,
        data: {'gender': _gender, 'avatar': _avatar, 'nickname': _nickname},
      );
      if (!mounted) return;
      final respData = data['data'] as Map<String, dynamic>?;
      if (respData == null) {
        AppToast.show(context, '保存失败');
        return;
      }
      final userId = respData['id'] as int? ?? ref.read(authProvider).userId;
      await StorageService.saveBool(
        AppConstants.storageInitialProfileCompleted,
        true,
      );
      final cached = StorageService.getUserInfo() ?? <String, dynamic>{};
      cached.addAll(respData);
      await StorageService.saveUserInfo(cached);
      if (userId != null) {
        await StorageService.saveUserId(userId);
      }
      await ref.read(authProvider.notifier).fetchUserInfo();
      if (!mounted) return;
      context.go(AppRoutes.index);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmLogout() async {
    if (_submitting || _loggingOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loggingOut = true);
    try {
      await ref.read(authProvider.notifier).logout();
      if (!mounted) return;
      context.go(AppRoutes.login);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final genderOptions = [
      _GenderOption(label: '男生', value: 'male'),
      _GenderOption(label: '女生', value: 'female'),
    ];
    final isBusy = _loading || _submitting || _loggingOut;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('初始资料'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                _buildAvatarPanel(),
                const SizedBox(height: 28),
                _buildNicknamePanel(),
                const SizedBox(height: 28),
                _buildGenderSection(genderOptions),
                const SizedBox(height: 32),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: isBusy ? null : _complete,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text(
                            '进入',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: isBusy ? null : _confirmLogout,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      side: const BorderSide(color: AppTheme.dividerColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: _loggingOut
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            '退出登录',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '头像',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppTheme.dividerColor),
                        boxShadow: AppTheme.elevatedShadow,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: _avatar.isEmpty
                            ? const Center(
                                child: Icon(
                                  Icons.person_outline,
                                  size: 64,
                                  color: AppTheme.textHint,
                                ),
                              )
                            : Image.network(
                                toAbsoluteMediaUrl(_avatar),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        size: 48,
                                        color: AppTheme.textHint,
                                      ),
                                    ),
                              ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: _buildDiceButton(
                      onPressed: (_loading || _submitting || _loggingOut)
                          ? null
                          : _randomAvatar,
                      tooltip: '换头像',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNicknamePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '昵称',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppTheme.dividerColor),
            boxShadow: AppTheme.elevatedShadow,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _nickname.isEmpty ? '暂无昵称' : _nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: _nickname.isEmpty ? 15 : 22,
                    fontWeight: FontWeight.w700,
                    color: _nickname.isEmpty
                        ? AppTheme.textHint
                        : AppTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _buildDiceButton(
                onPressed: (_loading || _submitting || _loggingOut)
                    ? null
                    : _randomNickname,
                tooltip: '换昵称',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGenderSection(List<_GenderOption> genderOptions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '性别',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Center(
          child: ToggleButtons(
            isSelected: genderOptions
                .map((item) => item.value == _gender)
                .toList(),
            onPressed: (_loading || _submitting || _loggingOut)
                ? null
                : (index) => _handleGenderChange(genderOptions[index].value),
            borderRadius: BorderRadius.circular(14),
            selectedColor: Colors.white,
            fillColor: AppTheme.primaryColor,
            color: AppTheme.textSecondary,
            constraints: const BoxConstraints(minHeight: 44, minWidth: 120),
            children: genderOptions
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(item.label),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDiceButton({
    required VoidCallback? onPressed,
    required String tooltip,
  }) {
    return Material(
      color: onPressed == null ? AppTheme.dividerColor : AppTheme.primaryColor,
      elevation: onPressed == null ? 0 : 2,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: const Icon(Icons.casino_outlined),
        color: Colors.white,
        iconSize: 22,
        constraints: const BoxConstraints.tightFor(width: 46, height: 46),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _GenderOption {
  final String label;
  final String value;

  const _GenderOption({required this.label, required this.value});
}
