# 补充页面、注册流程、主播角色切换实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成登录注册改造、补充页面、主播角色切换、Token Bug修复

**Architecture:** 后端先完成接口改造，前端按页面逐个实现，最后统一测试

**Tech Stack:** Flutter (Riverpod/go_router) + FastAPI (Tortoise ORM) + MySQL

---

## 一、文件结构

### 后端文件
| 文件 | 说明 |
|------|------|
| `backend/app/api/v1/app/register.py` | 修改 login/register 接口 |
| `backend/app/api/v1/app/agreement.py` | 新增：用户协议接口 |
| `backend/app/api/v1/app/privacy.py` | 新增：隐私政策接口 |
| `backend/app/api/v1/app/password.py` | 新增：修改密码接口 |
| `backend/app/settings/config.py` | 修改 JWT 过期时间 |

### 前端文件
| 文件 | 说明 |
|------|------|
| `huanxi/lib/modules/auth/login_page.dart` | 去除验证码切换 |
| `huanxi/lib/modules/auth/register_page.dart` | 新增：注册页 |
| `huanxi/lib/modules/settings/agreement_page.dart` | 新增：用户协议页 |
| `huanxi/lib/modules/settings/privacy_page.dart` | 新增：隐私政策页 |
| `huanxi/lib/modules/settings/change_password_page.dart` | 新增：密码修改页 |
| `huanxi/lib/modules/home/profile_page.dart` | 新增主播功能 |
| `huanxi/lib/app/routes/app_router.dart` | 新增路由 + 401 处理 |
| `huanxi/lib/app/providers/auth_provider.dart` | 新增登出跳转逻辑 |
| `huanxi/pubspec.yaml` | 新增 flutter_markdown 依赖 |

---

## 二、实施任务

### Task 1: 后端 - 修改登录/注册接口

**Files:**
- Modify: `backend/app/api/v1/app/register.py:1-74`

- [ ] **Step 1: 读取当前 register.py 代码**

```python
# 查看当前 login 和 register 接口
cat backend/app/api/v1/app/register.py
```

- [ ] **Step 2: 修改 login 接口 - 去掉 code 支持**

定位 `app_login` 函数，将:
```python
if req_in.password:
    if not verify_password(req_in.password, app_user.password or ...):
        return Fail(code=401, msg='密码错误')
elif req_in.code:
    if req_in.code != '123456':
        return Fail(code=401, msg='验证码错误')
else:
    return Fail(code=400, msg='请提供密码或验证码')
```
改为:
```python
if not req_in.password:
    return Fail(code=400, msg='请输入密码')
if not verify_password(req_in.password, app_user.password or ''):
    return Fail(code=401, msg='密码错误')
```

- [ ] **Step 3: 修改 register 接口 - 去掉 code 字段**

将 `AppRegisterIn` 的 `code` 字段删除，修改 `app_register` 函数去掉验证码校验。

- [ ] **Step 4: 测试验证**

```bash
cd backend && python -c '
from app.schemas.app_user import AppLoginIn, AppRegisterIn
print(AppLoginIn.model_fields)
print(AppRegisterIn.model_fields)
'
```

- [ ] **Step 5: 提交**

```bash
git add backend/app/api/v1/app/register.py
git commit -m 'fix: login/register 改为纯密码方式'
```

---

### Task 2: 后端 - 新增协议和政策接口

**Files:**
- Create: `backend/app/api/v1/app/agreement.py`
- Create: `backend/app/api/v1/app/privacy.py`

- [ ] **Step 1: 创建 agreement.py**

```python
from fastapi import APIRouter
from app.core.app_auth import DependAppAuth
from app.schemas.base import Success

router = APIRouter()

# 开发期用静态内容，后续可改为从数据库读取
AGREEMENT_CONTENT = '''
# 用户协议

## 第一条 服务条款的确认和接纳
欢喜平台所有权和运营权归欢喜科技所有。用户在使用本平台服务时，应遵守以下条款...

## 第二条 用户行为规范
用户不得利用本平台从事以下行为...
'''

@router.get('/agreement', summary='获取用户协议')
async def get_agreement():
    return Success(data={'content': AGREEMENT_CONTENT})
'''
```

写入 `backend/app/api/v1/app/agreement.py`

- [ ] **Step 2: 创建 privacy.py**

```python
from fastapi import APIRouter
from app.core.app_auth import DependAppAuth
from app.schemas.base import Success

router = APIRouter()

PRIVACY_CONTENT = '''
# 隐私政策

## 第一条 信息收集
我们收集以下信息以提供服务...
'''

@router.get('/privacy', summary='获取隐私政策')
async def get_privacy():
    return Success(data={'content': PRIVACY_CONTENT})
'''
```

写入 `backend/app/api/v1/app/privacy.py`

- [ ] **Step 3: 注册路由**

在 `backend/app/api/v1/app/__init__.py` 或 `app/__init__.py` 中添加:
```python
from app.api.v1.app import agreement, privacy

app.include_router(agreement.router, prefix='/app', tags=['app'])
app.include_router(privacy.router, prefix='/app', tags=['app'])
```

查找并修改 `backend/app/api/v1/app/__init__.py` 或 `backend/app/__init__.py`

- [ ] **Step 4: 测试**

```bash
curl http://localhost:9999/api/v1/app/agreement
curl http://localhost:9999/api/v1/app/privacy
```

- [ ] **Step 5: 提交**

```bash
git add backend/app/api/v1/app/agreement.py backend/app/api/v1/app/privacy.py
git commit -m 'feat: 新增用户协议和隐私政策接口'
```

---

### Task 3: 后端 - 新增修改密码接口

**Files:**
- Create: `backend/app/api/v1/app/password.py`

- [ ] **Step 1: 创建 password.py**

```python
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.core.app_auth import DependAppAuth, AppAuthControl
from app.models import AppUser
from app.schemas.base import Fail, Success
from app.utils.password import verify_password, get_password_hash

router = APIRouter()

class ChangePasswordIn(BaseModel):
    old_password: str
    new_password: str

@router.post('/change_password', summary='修改密码')
async def change_password(req_in: ChangePasswordIn, current_user: AppUser = DependAppAuth):
    # 校验旧密码
    if not verify_password(req_in.old_password, current_user.password or ''):
        return Fail(code=401, msg='原密码错误')
    
    # 更新密码
    current_user.password = get_password_hash(req_in.new_password)
    await current_user.save()
    
    return Success(msg='密码修改成功')
'''
```

写入 `backend/app/api/v1/app/password.py`

- [ ] **Step 2: 注册路由**

在 app 的路由注册处添加 `password.router`

- [ ] **Step 3: 测试**

```bash
# 需要先登录获取 token
curl -X POST http://localhost:9999/api/v1/app/change_password -H 'token: YOUR_TOKEN' -d '{\"old_password\":\"123456\",\"new_password\":\"654321\"}'
```

- [ ] **Step 4: 提交**

```bash
git add backend/app/api/v1/app/password.py
git commit -m 'feat: 新增修改密码接口'
```

---

### Task 4: 后端 - Token 过期时间改为 30 天

**Files:**
- Modify: `backend/app/settings/config.py:33`

- [ ] **Step 1: 修改配置**

将:
```python
JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 days
```
改为:
```python
JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 30  # 30 days
```

- [ ] **Step 2: 提交**

```bash
git add backend/app/settings/config.py
git commit -m 'fix: Token 过期时间改为 30 天'
```

---

### Task 5: 前端 - 添加 flutter_markdown 依赖

**Files:**
- Modify: `huanxi/pubspec.yaml`

- [ ] **Step 1: 添加依赖**

在 `dependencies` 中添加:
```yaml
  flutter_markdown: ^0.7.4+2
```

- [ ] **Step 2: 安装依赖**

```bash
cd huanxi && flutter pub get
```

- [ ] **Step 3: 提交**

```bash
git add huanxi/pubspec.yaml huanxi/pubspec.lock
git commit -m 'feat: 添加 flutter_markdown 依赖'
```

---

### Task 6: 前端 - 登录页改造

**Files:**
- Modify: `huanxi/lib/modules/auth/login_page.dart`

- [ ] **Step 1: 读取当前代码**

```dart
// 查看当前 login_page.dart 结构
head -80 huanxi/lib/modules/auth/login_page.dart
```

- [ ] **Step 2: 去除验证码切换**

删除 `_usePassword` 相关逻辑和「使用验证码登录」/「使用密码登录」切换按钮。

具体改动:
1. 删除 `_usePassword` 变量和切换按钮 (第 199-215 行)
2. 简化密码输入框，去掉验证码相关 suffixIcon
3. 去掉开发期验证码提示框（第 217-243 行）

- [ ] **Step 3: 运行 analyze**

```bash
cd huanxi && flutter analyze
```

- [ ] **Step 4: 提交**

```bash
git add huanxi/lib/modules/auth/login_page.dart
git commit -m 'feat: 登录页改为纯密码登录'
```

---

### Task 7: 前端 - 新增注册页

**Files:**
- Create: `huanxi/lib/modules/auth/register_page.dart`
- Modify: `huanxi/lib/app/routes/app_router.dart`
- Modify: `huanxi/lib/core/constants/api_endpoints.dart`

- [ ] **Step 1: 添加 API 端点**

在 `huanxi/lib/core/constants/api_endpoints.dart` 添加:
```dart
/// 注册
static const String appRegister = 'app/register';
```

- [ ] **Step 2: 创建 register_page.dart**

参考 login_page.dart 风格，创建注册页:
- 字段：手机号、密码、确认密码
- 校验：手机号 11 位、密码不为空、两次密码一致
- 提交：调用 `POST /app/register`
- 成功后跳转登录页

写入 `huanxi/lib/modules/auth/register_page.dart`

- [ ] **Step 3: 添加路由**

在 `app_router.dart` 添加:
```dart
import '../../modules/auth/register_page.dart';

// 在 routes 中添加
GoRoute(
  path: AppRoutes.register,
  builder: (context, state) => const RegisterPage(),
),

// 在 AppRoutes 类中添加
static const String register = '/register';
```

- [ ] **Step 4: 登录页添加注册链接**

在登录页底部「登录即表示同意...」下方添加:
```dart
TextButton(
  onPressed: () => context.push(AppRoutes.register),
  child: const Text('没有账号？去注册'),
),
```

- [ ] **Step 5: 运行 analyze**

```bash
cd huanxi && flutter analyze
```

- [ ] **Step 6: 提交**

```bash
git add huanxi/lib/modules/auth/register_page.dart huanxi/lib/app/routes/app_router.dart huanxi/lib/core/constants/api_endpoints.dart
git commit -m 'feat: 新增注册页'
```

---

### Task 8: 前端 - 用户协议页

**Files:**
- Create: `huanxi/lib/modules/settings/agreement_page.dart`
- Modify: `huanxi/lib/app/routes/app_router.dart`

- [ ] **Step 1: 创建 agreement_page.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../core/network/dio_client.dart';
import '../../core/constants/api_endpoints.dart';
import '../../app/theme/app_theme.dart';

class AgreementPage extends StatefulWidget {
  const AgreementPage({super.key});

  @override
  State<AgreementPage> createState() => _AgreementPageState();
}

class _AgreementPageState extends State<AgreementPage> {
  String? _content;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      final data = await DioClient.instance.apiGet(ApiEndpoints.agreement);
      setState(() {
        _content = data['data']?['content'] as String?;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('用户协议')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _content == null
              ? const Center(child: Text('加载失败'))
              : Markdown(
                  data: _content!,
                  padding: const EdgeInsets.all(16),
                  styleSheet: MarkdownStyleSheet(
                    h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    p: const TextStyle(fontSize: 16, height: 1.6),
                  ),
                ),
    );
  }
}
```

- [ ] **Step 2: 添加 API 端点**

在 `api_endpoints.dart` 添加:
```dart
static const String agreement = 'app/agreement';
```

- [ ] **Step 3: 添加路由**

在 `app_router.dart` 添加:
```dart
GoRoute(
  path: '/settings/agreement',
  builder: (context, state) => const AgreementPage(),
),
```

- [ ] **Step 4: 设置页关联**

修改 `settings_page.dart` 的「用户协议」点击事件:
```dart
_SettingsTile(
  icon: Icons.description_outlined,
  title: '用户协议',
  onTap: () => context.push('/settings/agreement'),
),
```

- [ ] **Step 5: 提交**

```bash
git add huanxi/lib/modules/settings/agreement_page.dart huanxi/lib/app/routes/app_router.dart huanxi/lib/core/constants/api_endpoints.dart huanxi/lib/modules/settings/settings_page.dart
git commit -m 'feat: 新增用户协议页'
```

---

### Task 9: 前端 - 隐私政策页

**Files:**
- Create: `huanxi/lib/modules/settings/privacy_page.dart`
- Modify: `huanxi/lib/app/routes/app_router.dart`
- Modify: `huanxi/lib/modules/settings/settings_page.dart`

- [ ] **Step 1: 创建 privacy_page.dart**

参考 agreement_page.dart 创建，仅修改标题和 API 端点为 `privacy`

- [ ] **Step 2: 添加 API 端点**

```dart
static const String privacy = 'app/privacy';
```

- [ ] **Step 3: 添加路由**

```dart
GoRoute(
  path: '/settings/privacy',
  builder: (context, state) => const PrivacyPage(),
),
```

- [ ] **Step 4: 设置页关联**

修改「隐私政策」点击事件

- [ ] **Step 5: 提交**

```bash
git add huanxi/lib/modules/settings/privacy_page.dart
git commit -m 'feat: 新增隐私政策页'
```

---

### Task 10: 前端 - 密码修改页

**Files:**
- Create: `huanxi/lib/modules/settings/change_password_page.dart`
- Modify: `huanxi/lib/app/routes/app_router.dart`

- [ ] **Step 1: 创建 change_password_page.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/dio_client.dart';
import '../../core/constants/api_endpoints.dart';
import '../../app/theme/app_theme.dart';

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

    if (oldPwd.isEmpty || newPwd.isEmpty || confirmPwd.isEmpty) {
      setState(() => _error = '请填写完整');
      return;
    }
    if (newPwd != confirmPwd) {
      setState(() => _error = '两次密码不一致');
      return;
    }
    if (newPwd.length < 6) {
      setState(() => _error = '密码长度至少6位');
      return;
    }

    setState(() => _error = null);

    try {
      setState(() => _isLoading = true);
      await DioClient.instance.apiPost(
        ApiEndpoints.changePassword,
        data: {'old_password': oldPwd, 'new_password': newPwd},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密码修改成功')),
        );
        context.pop();
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('修改密码')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _oldPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '旧密码'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '新密码'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '确认新密码'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppTheme.errorColor)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('确认修改'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 添加 API 端点**

```dart
static const String changePassword = 'app/change_password';
```

- [ ] **Step 3: 添加路由**

```dart
GoRoute(
  path: '/settings/password',
  builder: (context, state) => const ChangePasswordPage(),
),
```

- [ ] **Step 4: 设置页关联**

修改「账号与安全」点击事件:
```dart
onTap: () => context.push('/settings/password'),
```

- [ ] **Step 5: 提交**

```bash
git add huanxi/lib/modules/settings/change_password_page.dart
git commit -m 'feat: 新增密码修改页'
```

---

### Task 11: 前端 - 主播角色切换

**Files:**
- Modify: `huanxi/lib/modules/home/profile_page.dart`

- [ ] **Step 1: 读取当前 profile_page.dart**

查看「我的」页面当前结构，找到功能列表区域（`_buildMenuTile` 调用处）

- [ ] **Step 2: 判断主播角色**

在 `ProfilePage` 的 `build` 方法中，根据 `authState.appRole == 'anchor'` 判断

- [ ] **Step 3: 修改功能列表**

在 `_buildMenuTile` 调用列表中，对主播添加以下功能:

1. 头像下方显示「认证主播」标识
2. 功能列表中新增「在线接单」Switch
3. 功能列表中新增「累计收益 ¥XXX」
4. 功能列表中新增「提现」入口

具体实现参考:
```dart
// 在 ProfilePage build 方法中
final isAnchor = authState.appRole == 'anchor';

// 头像下方（增加）
if (isAnchor) ...[
  const SizedBox(height: 4),
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: AppTheme.secondaryColor,
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Text('认证主播', style: TextStyle(color: Colors.white, fontSize: 12)),
  ),
],

// 功能列表中新增
if (isAnchor) ...[
  _buildMenuTile(..., title: '在线接单', trailing: Switch(...)),
  _buildMenuTile(..., title: '累计收益 ¥${authState.balance.toStringAsFixed(2)}'),
  _buildMenuTile(..., title: '提现'),
],
```

- [ ] **Step 4: 提交**

```bash
git add huanxi/lib/modules/home/profile_page.dart
git commit -m 'feat: 主播角色显示额外功能'
```

---

### Task 12: 前端 - Token 401 跳转修复

**Files:**
- Modify: `huanxi/lib/app/routes/app_router.dart`

- [ ] **Step 1: 添加验证逻辑**

在 `app_router.dart` 的 `redirect` 方法中添加 token 验证:

```dart
redirect: (context, state) async {
  final token = StorageService.getToken();
  if (token != null && token.isNotEmpty) {
    // 验证 token 是否有效
    try {
      await DioClient.instance.apiGet('app/user/info');
    } catch (e) {
      // token 无效，清除并跳转登录
      await StorageService.clearUserData();
      // 清理 authProvider 状态
      // 返回登录页
      return AppRoutes.login;
    }
  }
  // ... 原有逻辑
},
```

注意：这会导致每次页面跳转都调用一次 API，建议改为仅在特定时机验证（如应用恢复前台时），或者简化处理：在页面请求返回 401 时统一跳转。

简化方案：在 `api_interceptor.dart` 的 401 处理中触发路由跳转

- [ ] **Step 2: 更简化的 401 处理**

在 `api_interceptor.dart` 中，将 `UnauthorizedException` 抛出改为直接触发跳转：

由于 `api_interceptor.dart` 无法直接访问 GoRouter，考虑在 provider 层处理：

在 `auth_provider.dart` 中添加:
```dart
/// 401 时清除数据并标记需要跳转
Future<void> handleUnauthorized() async {
  await StorageService.clearUserData();
  state = const AuthState();
}
```

在调用 API 的地方 catch `UnauthorizedException` 后调用此方法。

但最简单的方式是在路由层处理：应用启动时验证 token，而非每次跳转验证。

- [ ] **Step 3: 应用启动时验证（推荐）**

在 `main.dart` 或 `splash_page.dart` 中，登录后调用 `/app/user/info` 验证 token，如果失败则跳转登录页。

修改 `auth_provider.dart` 的 `init` 方法:
```dart
Future<void> init() async {
  final token = StorageService.getToken();
  if (token != null && token.isNotEmpty) {
    // 尝试从本地缓存加载
    final cachedInfo = StorageService.getUserInfo();
    if (cachedInfo != null) {
      state = state.copyWith(...);
    }
    
    // 异步验证并获取最新数据
    try {
      await fetchUserInfo();
    } catch (e) {
      // token 无效，清除
      await StorageService.clearUserData();
      state = const AuthState();
    }
  } else {
    state = const AuthState();
  }
}
```

- [ ] **Step 4: 提交**

```bash
git add huanxi/lib/app/providers/auth_provider.dart
git commit -m 'fix: Token 无效时自动清除并重置状态'
```

---

### Task 13: 整体测试与验证

- [ ] **Step 1: 运行 flutter analyze**

```bash
cd huanxi && flutter analyze
```

确保无警告无错误

- [ ] **Step 2: 构建 APK**

```bash
cd huanxi && flutter build apk --debug
```

- [ ] **Step 3: 测试登录/注册流程**

- [ ] **Step 4: 测试协议/政策/密码修改页面**

- [ ] **Step 5: 用主播账号测试额外功能显示**

- [ ] **Step 6: 测试 Token 过期场景**

- [ ] **Step 7: 提交**

```bash
git add .
git commit -m 'feat: 完成补充页面、注册流程、主播角色切换'
```

---

## 三、执行顺序

1. **Task 1-4**: 后端接口改造
2. **Task 5**: 前端依赖添加
3. **Task 6-7**: 登录注册改造
4. **Task 8-10**: 补充页面
5. **Task 11**: 主播角色
6. **Task 12**: Token Bug 修复
7. **Task 13**: 整体测试

---

Plan complete and saved to `docs/superpowers/plans/2026-04-14-app-shell-plan.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?