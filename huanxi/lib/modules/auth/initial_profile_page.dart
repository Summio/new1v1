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
  int _avatarCount = 0;
  int _nicknamePrefixCount = 0;
  int _nicknameSuffixCount = 0;
  int _nicknameComboCount = 0;
  bool _loading = false;
  bool _submitting = false;

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
        _avatarCount = _parseInt(respData['avatar_count']);
        _nicknamePrefixCount = _parseInt(respData['nickname_prefix_count']);
        _nicknameSuffixCount = _parseInt(respData['nickname_suffix_count']);
        _nicknameComboCount = _parseInt(respData['nickname_combo_count']);
      });
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _randomAvatar() async {
    if (_submitting) return;
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
    if (_submitting) return;
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
    if (gender == _gender || _submitting) return;
    setState(() => _gender = gender);
    await _loadOptions();
  }

  Future<void> _complete() async {
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

  int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final genderOptions = [
      _GenderOption(label: '男生', value: 'male'),
      _GenderOption(label: '女生', value: 'female'),
    ];

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
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppTheme.elevatedShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ToggleButtons(
                        isSelected: genderOptions
                            .map((item) => item.value == _gender)
                            .toList(),
                        onPressed: (index) =>
                            _handleGenderChange(genderOptions[index].value),
                        borderRadius: BorderRadius.circular(12),
                        selectedColor: Colors.white,
                        fillColor: AppTheme.primaryColor,
                        constraints: const BoxConstraints(
                          minHeight: 44,
                          minWidth: 120,
                        ),
                        children: genderOptions
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Text(item.label),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildAvatarPanel()),
                          const SizedBox(width: 12),
                          Expanded(child: _buildNicknamePanel()),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppTheme.elevatedShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _statRow('头像数量', '$_avatarCount'),
                      const SizedBox(height: 8),
                      _statRow(
                        '前缀/后缀',
                        '$_nicknamePrefixCount / $_nicknameSuffixCount',
                      ),
                      const SizedBox(height: 8),
                      _statRow('可组合昵称', '$_nicknameComboCount'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: (_loading || _submitting) ? null : _complete,
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
                            '完成',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
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
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.backgroundColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _avatar.isEmpty
                  ? const Center(
                      child: Icon(
                        Icons.person_outline,
                        size: 56,
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
                              size: 44,
                              color: AppTheme.textHint,
                            ),
                          ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _submitting ? null : _randomAvatar,
          icon: const Icon(Icons.shuffle),
          label: const Text('换头像'),
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
          height: 150,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Center(
            child: Text(
              _nickname.isEmpty ? '暂无昵称' : _nickname,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: _nickname.isEmpty ? 14 : 24,
                fontWeight: FontWeight.w600,
                color: _nickname.isEmpty
                    ? AppTheme.textHint
                    : AppTheme.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _submitting ? null : _randomNickname,
          icon: const Icon(Icons.shuffle),
          label: const Text('换昵称'),
        ),
      ],
    );
  }

  Widget _statRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _GenderOption {
  final String label;
  final String value;

  const _GenderOption({required this.label, required this.value});
}
