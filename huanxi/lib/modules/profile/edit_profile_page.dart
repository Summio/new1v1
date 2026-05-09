import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers/auth_provider.dart';
import '../../app/theme/app_theme.dart';
import 'package:huanxi/core/utils/app_toast.dart';

class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final ImagePicker _imagePicker = ImagePicker();
  late TextEditingController _nicknameController;
  late TextEditingController _avatarController;
  late TextEditingController _signatureController;
  late TextEditingController _heightController;
  late TextEditingController _weightController;

  bool _isSaving = false;
  String _gender = 'secret';
  DateTime? _birthDate;
  String _locationCity = '';
  List<String> _albumPhotos = <String>[];
  String? _coverUrl;

  @override
  void initState() {
    super.initState();
    final authState = ref.read(authProvider);
    _nicknameController = TextEditingController(text: authState.username ?? '');
    _avatarController = TextEditingController(text: authState.avatar ?? '');
    _signatureController = TextEditingController(
      text: authState.signature ?? '',
    );
    _heightController = TextEditingController(
      text: authState.heightCm == null ? '' : authState.heightCm.toString(),
    );
    _weightController = TextEditingController(
      text: authState.weightKg == null ? '' : authState.weightKg.toString(),
    );

    _gender = authState.gender;
    _locationCity = authState.locationCity ?? '';
    _albumPhotos = List<String>.from(authState.albumPhotos);
    _coverUrl = authState.coverUrl;

    final rawBirthDate = authState.birthDate;
    if (rawBirthDate != null && rawBirthDate.trim().isNotEmpty) {
      _birthDate = DateTime.tryParse(rawBirthDate.trim());
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _avatarController.dispose();
    _signatureController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  String _dateText(DateTime? value) {
    if (value == null) return '请选择出生日期';
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1950, 1, 1),
      lastDate: now,
      locale: const Locale('zh', 'CN'),
    );
    if (picked == null) return;
    setState(() {
      _birthDate = picked;
    });
  }

  Future<void> _pickLocationCity() async {
    final result = await _showCityPicker(context, initialValue: _locationCity);
    if (result == null) return;
    setState(() {
      _locationCity = result;
    });
  }

  void _addAlbumPhoto() {
    if (_albumPhotos.length >= 6) {
      AppToast.showSnackBar(context, const SnackBar(content: Text('相册最多6张')));
      return;
    }
    setState(() {
      _albumPhotos = [..._albumPhotos, ''];
    });
  }

  void _removeAlbumPhoto(int index) {
    final removed = _albumPhotos[index].trim();
    final next = List<String>.from(_albumPhotos)..removeAt(index);
    setState(() {
      _albumPhotos = next;
      if (_coverUrl != null && _coverUrl == removed) {
        _coverUrl = null;
      }
    });
  }

  void _updateAlbumPhoto(int index, String value) {
    final next = List<String>.from(_albumPhotos);
    next[index] = value;
    setState(() {
      _albumPhotos = next;
      if (_coverUrl != null && !_validAlbumList(next).contains(_coverUrl)) {
        _coverUrl = null;
      }
    });
  }

  List<String> _validAlbumList(List<String> source) {
    final out = <String>[];
    final seen = <String>{};
    for (final item in source) {
      final v = item.trim();
      if (v.isEmpty || seen.contains(v)) continue;
      seen.add(v);
      out.add(v);
    }
    return out;
  }

  Future<String?> _pickAndUploadImage() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final url = await ref
        .read(authProvider.notifier)
        .uploadProfileImage(bytes: bytes, filename: picked.name);
    if (url == null && mounted) {
      final err = ref.read(authProvider).error ?? '上传失败';
      AppToast.showSnackBar(context, SnackBar(content: Text(err)));
    }
    return url;
  }

  Future<void> _save() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      AppToast.showSnackBar(context, const SnackBar(content: Text('昵称不能为空')));
      return;
    }

    final heightText = _heightController.text.trim();
    final weightText = _weightController.text.trim();
    final heightCm = heightText.isEmpty ? null : int.tryParse(heightText);
    final weightKg = weightText.isEmpty ? null : int.tryParse(weightText);

    if (heightText.isNotEmpty && heightCm == null) {
      AppToast.showSnackBar(context, const SnackBar(content: Text('身高请输入数字')));
      return;
    }
    if (weightText.isNotEmpty && weightKg == null) {
      AppToast.showSnackBar(context, const SnackBar(content: Text('体重请输入数字')));
      return;
    }

    final album = _validAlbumList(_albumPhotos);
    if (album.length > 6) {
      AppToast.showSnackBar(context, const SnackBar(content: Text('相册最多6张')));
      return;
    }

    if (_coverUrl != null &&
        _coverUrl!.trim().isNotEmpty &&
        !album.contains(_coverUrl!.trim())) {
      AppToast.showSnackBar(
        context,
        const SnackBar(content: Text('封面必须从相册中选择')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final payload = <String, dynamic>{
      'nickname': nickname,
      'avatar': _avatarController.text.trim(),
      'signature': _signatureController.text.trim(),
      'gender': _gender,
      'birth_date': _birthDate == null ? null : _dateText(_birthDate),
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'location_city': _locationCity,
      'album_photos': album,
      'cover_url': (_coverUrl ?? '').trim(),
    };

    final ok = await ref.read(authProvider.notifier).updateProfile(payload);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (!ok) {
      final err = ref.read(authProvider).error ?? '保存失败';
      AppToast.showSnackBar(context, SnackBar(content: Text(err)));
      return;
    }

    AppToast.showSnackBar(context, const SnackBar(content: Text('资料已保存')));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final validAlbum = _validAlbumList(_albumPhotos);
    final avatarUrl = _avatarController.text.trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(title: const Text('编辑资料')),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('头像'),
              _buildSectionCard(
                child: Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(56),
                      onTap: () async {
                        final url = await _pickAndUploadImage();
                        if (url == null || !mounted) return;
                        setState(() {
                          _avatarController.text = url;
                        });
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 46,
                            backgroundColor: AppTheme.primaryColor.withValues(
                              alpha: 0.12,
                            ),
                            backgroundImage: avatarUrl.isNotEmpty
                                ? NetworkImage(avatarUrl)
                                : (authState.avatar != null &&
                                          authState.avatar!.trim().isNotEmpty
                                      ? NetworkImage(authState.avatar!.trim())
                                      : null),
                            child:
                                (avatarUrl.isEmpty &&
                                    (authState.avatar == null ||
                                        authState.avatar!.trim().isEmpty))
                                ? const Icon(
                                    Icons.person,
                                    size: 46,
                                    color: AppTheme.primaryColor,
                                  )
                                : null,
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.edit,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '点击头像更换',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              _buildSectionTitle('基本信息'),
              _buildSectionCard(
                child: Column(
                  children: [
                    TextField(
                      controller: _nicknameController,
                      decoration: const InputDecoration(
                        labelText: '昵称',
                        hintText: '请输入昵称',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      maxLength: 30,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _signatureController,
                      decoration: const InputDecoration(
                        labelText: '个性签名',
                        hintText: '写一句关于自己的介绍',
                        prefixIcon: Icon(Icons.edit_note_outlined),
                      ),
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 500,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _gender,
                      decoration: const InputDecoration(
                        labelText: '性别',
                        prefixIcon: Icon(Icons.wc),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'male', child: Text('男')),
                        DropdownMenuItem(value: 'female', child: Text('女')),
                        DropdownMenuItem(value: 'secret', child: Text('保密')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _gender = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildTapTile(
                      label: '出生日期',
                      value: _dateText(_birthDate),
                      icon: Icons.cake_outlined,
                      onTap: _pickBirthDate,
                    ),
                    const SizedBox(height: 12),
                    _buildTapTile(
                      label: '所在地',
                      value: _locationCity.isEmpty ? '请选择到市' : _locationCity,
                      icon: Icons.location_on_outlined,
                      onTap: _pickLocationCity,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _heightController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '身高(cm)',
                              hintText: '如 170',
                              prefixIcon: Icon(Icons.height),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _weightController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '体重(kg)',
                              hintText: '如 52',
                              prefixIcon: Icon(Icons.monitor_weight_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              _buildSectionTitle('相册与封面'),
              _buildSectionCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          '相册（${_validAlbumList(_albumPhotos).length}/6）',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        FilledButton.tonalIcon(
                          onPressed: _addAlbumPhoto,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('新增'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_albumPhotos.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(child: Text('还没有照片，点击“新增”添加')),
                      ),
                    ...List.generate(_albumPhotos.length, (index) {
                      final rawUrl = _albumPhotos[index].trim();
                      final hasImage = rawUrl.isNotEmpty;
                      final isCover =
                          _coverUrl != null && _coverUrl == rawUrl && hasImage;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: Colors.white,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: hasImage
                                      ? Image.network(
                                          rawUrl,
                                          fit: BoxFit.cover,
                                           errorBuilder: (_, _, _) =>
                                              const Icon(
                                                Icons.broken_image_outlined,
                                              ),
                                        )
                                      : const Icon(
                                          Icons.image_outlined,
                                          color: AppTheme.textHint,
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '照片 ${index + 1}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        isCover ? '当前封面' : '可用于封面',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isCover)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      '封面',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.primaryColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              alignment: WrapAlignment.spaceBetween,
                              children: [
                                TextButton.icon(
                                  onPressed: () async {
                                    final url = await _pickAndUploadImage();
                                    if (url == null || !mounted) return;
                                    _updateAlbumPhoto(index, url);
                                  },
                                  icon: const Icon(
                                    Icons.photo_library_outlined,
                                    size: 18,
                                  ),
                                  label: Text(hasImage ? '更换' : '上传'),
                                ),
                                TextButton.icon(
                                  onPressed: hasImage
                                      ? () {
                                          setState(() {
                                            _coverUrl = rawUrl;
                                          });
                                        }
                                      : null,
                                  icon: const Icon(
                                    Icons.image_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('设为封面'),
                                ),
                                TextButton.icon(
                                  onPressed: () => _removeAlbumPhoto(index),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  label: const Text('删除'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    if (validAlbum.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '上传相册图片后可设置封面',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              _buildSectionCard(
                child: _buildInfoTile(
                  '用户ID',
                  authState.userId?.toString() ?? '-',
                ),
              ),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('保存资料'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildTapTile({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        child: Row(
          children: [
            Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(color: AppTheme.textHint, fontSize: 14),
        ),
      ],
    );
  }
}

Future<String?> _showCityPicker(
  BuildContext context, {
  String initialValue = '',
}) async {
  const cityMap = <String, List<String>>{
    '北京市': ['北京市'],
    '天津市': ['天津市'],
    '上海市': ['上海市'],
    '重庆市': ['重庆市'],
    '河北省': ['石家庄市', '唐山市', '保定市', '廊坊市'],
    '山西省': ['太原市', '大同市', '运城市'],
    '辽宁省': ['沈阳市', '大连市', '鞍山市'],
    '吉林省': ['长春市', '吉林市'],
    '黑龙江省': ['哈尔滨市', '齐齐哈尔市'],
    '江苏省': ['南京市', '苏州市', '无锡市', '常州市'],
    '浙江省': ['杭州市', '宁波市', '温州市', '金华市'],
    '安徽省': ['合肥市', '芜湖市'],
    '福建省': ['福州市', '厦门市', '泉州市'],
    '江西省': ['南昌市', '赣州市'],
    '山东省': ['济南市', '青岛市', '烟台市'],
    '河南省': ['郑州市', '洛阳市', '南阳市'],
    '湖北省': ['武汉市', '襄阳市', '宜昌市'],
    '湖南省': ['长沙市', '株洲市'],
    '广东省': ['广州市', '深圳市', '佛山市', '东莞市'],
    '海南省': ['海口市', '三亚市'],
    '四川省': ['成都市', '绵阳市', '南充市'],
    '贵州省': ['贵阳市', '遵义市'],
    '云南省': ['昆明市', '曲靖市'],
    '陕西省': ['西安市', '咸阳市'],
    '甘肃省': ['兰州市'],
    '青海省': ['西宁市'],
    '内蒙古自治区': ['呼和浩特市', '包头市'],
    '广西壮族自治区': ['南宁市', '桂林市'],
    '西藏自治区': ['拉萨市'],
    '宁夏回族自治区': ['银川市'],
    '新疆维吾尔自治区': ['乌鲁木齐市', '喀什市'],
    '香港特别行政区': ['香港特别行政区'],
    '澳门特别行政区': ['澳门特别行政区'],
    '台湾省': ['台北市', '高雄市'],
  };

  final provinces = cityMap.keys.toList();
  String selectedProvince = provinces.first;
  String selectedCity = cityMap[selectedProvince]!.first;

  if (initialValue.contains('-')) {
    final split = initialValue.split('-');
    if (split.length == 2 && cityMap.containsKey(split[0])) {
      selectedProvince = split[0];
      final cities = cityMap[selectedProvince]!;
      if (cities.contains(split[1])) {
        selectedCity = split[1];
      } else {
        selectedCity = cities.first;
      }
    }
  }

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final cities = cityMap[selectedProvince] ?? const <String>[];
          if (!cities.contains(selectedCity) && cities.isNotEmpty) {
            selectedCity = cities.first;
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '选择所在地（到市）',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: selectedProvince,
                    decoration: const InputDecoration(labelText: '省/自治区/直辖市'),
                    items: provinces
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setSheetState(() {
                        selectedProvince = value;
                        final nextCities =
                            cityMap[selectedProvince] ?? const <String>[];
                        selectedCity = nextCities.isEmpty
                            ? ''
                            : nextCities.first;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: cities.contains(selectedCity)
                        ? selectedCity
                        : null,
                    decoration: const InputDecoration(labelText: '市'),
                    items: cities
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setSheetState(() {
                        selectedCity = value;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: selectedCity.isEmpty
                              ? null
                              : () => Navigator.of(
                                  sheetContext,
                                ).pop('$selectedProvince-$selectedCity'),
                          child: const Text('确定'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
