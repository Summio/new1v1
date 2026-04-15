# 腾讯 IM 接入实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 接入腾讯云 IM，实现基础单聊功能（文字消息），支持消息服务端漫游

**Architecture:** 后端负责生成 UserSig（使用腾讯 TLSSigAPIv2），前端使用腾讯 IM SDK 进行消息收发

**Tech Stack:**
- 后端：Python FastAPI + tencentcloud-sdk-python-core
- 前端：Flutter + tencentcloud_im_sdk

---

## 文件结构

```
backend/
├── app/
│   ├── settings/
│   │   ├── config.py       # 已存在，追加 IM 配置导入
│   │   └── im.py          # 新增：IM 配置类
│   └── api/v1/app/
│       └── im.py          # 修改：UserSig 生成逻辑

huanxi/
├── pubspec.yaml           # 修改：添加 IM SDK 依赖
├── lib/
│   ├── services/
│   │   └── im_service.dart  # 新增：IM 服务封装
│   └── modules/im/
│       └── im_page.dart    # 修改：接入真实 IM
```

---

## Task 1: 后端 IM 配置

**Files:**
- Create: `backend/app/settings/im.py`
- Modify: `backend/app/settings/config.py:10` (添加导入)

- [ ] **Step 1: 创建 `backend/app/settings/im.py`**

```python
import os
import typing
from pydantic_settings import BaseSettings


class IMSettings(BaseSettings):
    """腾讯 IM 配置"""
    model_config = {"env_file": ".env", "extra": "ignore"}

    # 腾讯 IM 配置（生产环境必填）
    IM_SDKAPPID: typing.Optional[int] = None
    IM_SECRETKEY: typing.Optional[str] = None

    @property
    def is_configured(self) -> bool:
        """检查 IM 配置是否完整"""
        return bool(self.IM_SDKAPPID and self.IM_SECRETKEY)


im_settings = IMSettings()
```

- [ ] **Step 2: 修改 `backend/app/settings/config.py` 添加导入**

在文件末尾 `settings = Settings()` 之前添加：

```python
# 腾讯 IM 配置
try:
    from app.settings.im import im_settings
except ImportError:
    im_settings = None
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/settings/im.py backend/app/settings/config.py
git commit -m "feat: 添加腾讯 IM 配置模块"
```

---

## Task 2: 后端 UserSig 生成

**Files:**
- Modify: `backend/app/api/v1/app/im.py:1-35`

- [ ] **Step 1: 修改 `backend/app/api/v1/app/im.py` 替换 Mock 实现**

```python
import time

from fastapi import APIRouter

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_ID
from app.schemas.app_api import IMSigOut
from app.schemas.base import Fail, Success
from app.settings.config import settings

router = APIRouter()


@router.get("/im/usersig", summary="获取IM UserSig", dependencies=[DependAppAuth])
async def get_usersig():
    """
    获取腾讯云 IM 的 UserSig。
    使用 TLSSigAPIv2 生成真实签名。
    """
    from app.settings.im import im_settings

    user_id = CTX_APP_USER_ID.get()

    # 检查 IM 配置
    if not im_settings or not im_settings.is_configured:
        # 配置缺失时返回提示（开发期可继续使用 Mock）
        return Fail(msg="IM 配置未完成，请联系管理员配置 IM_SDKAPPID 和 IM_SECRETKEY")

    try:
        # 使用腾讯云签名库
        from tencentcloud.imsig.v2 import TLSSigAPIv2

        api = TLSSigAPIv2(im_settings.IM_SDKAPPID, im_settings.IM_SECRETKEY)
        usersig = api.generate_user_sig(
            userid=f"huanxi_{user_id}",
            expire=3600 * 24 * 7  # 7天有效期
        )
        expired_time = int(time.time()) + 3600 * 24 * 7

---

## Task 3: 前端添加 IM SDK 依赖

**Files:**
- Modify: `huanxi/pubspec.yaml`

- [ ] **Step 1: 查看 `huanxi/pubspec.yaml` 结构**

```bash
cat huanxi/pubspec.yaml
```

- [ ] **Step 2: 添加 IM SDK 依赖（版本根据实际发布确定）**

在 `dependencies:` 下添加：

```yaml
  # 腾讯 IM SDK
  # 注意：实际包名需在 pub.dev 确认，以下为占位符
  # 执行: flutter pub add tencentcloud_im_sdk
  tencentcloud_im_sdk: ^6.9.0
```

- [ ] **Step 3: Commit**

```bash
git add huanxi/pubspec.yaml
git commit -m "feat: 添加腾讯 IM SDK 依赖"
```

---

## Task 4: 前端 IM Service 封装

**Files:**
- Create: `huanxi/lib/services/im_service.dart`

- [ ] **Step 1: 创建 `huanxi/lib/services/im_service.dart`**

```dart
import 'package:tencentcloud_im_sdk/tencentcloud_im_sdk.dart';

/// IM 服务封装
class IMService {
  static final IMService _instance = IMService._();
  factory IMService() => _instance;
  IMService._();

  V2TIMManager? _timManager;
  String? _currentUserId;
  bool _isInitialized = false;

  /// 当前登录用户ID
  String? get currentUserId => _currentUserId;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 初始化 IM SDK
  Future<void> init({
    required int sdkAppId,
    LogLevel logLevel = LogLevel.logLevelVerbose,
  }) async {
    if (_isInitialized) return;

    V2TIMManager.setLogLevel(logLevel);
    await V2TIMManager.initSDK(sdkAppId: sdkAppId);
    _timManager = V2TIMManager();
    _isInitialized = true;
  }

  /// 登录 IM
  /// [userId] 用户ID（需与后端生成 usersig 时一致，前缀 huanxi_）
  /// [userSig] 后端返回的签名
  Future<void> login({
    required String userId,
    required String userSig,
  }) async {
    if (!_isInitialized) {
      throw Exception('IM SDK 未初始化，请先调用 init()');
    }

    final result = await _timManager!.login(
      userID: userId,
      userSig: userSig,
    );

    if (result.code != 0) {
      throw Exception('IM 登录失败: ${result.desc}');
    }

    _currentUserId = userId;
  }

  /// 登出 IM
  Future<void> logout() async {
    if (_timManager == null) return;

    final result = await _timManager!.logout();
    if (result.code != 0) {
      throw Exception('IM 登出失败: ${result.desc}');
    }

    _currentUserId = null;
  }

  /// 发送文本消息
  /// [receiver] 接收者 userID
  /// [text] 消息内容
  Future<V2TIMMessage> sendTextMessage({
    required String receiver,
    required String text,
  }) async {
    if (!_isInitialized || _timManager == null) {
      throw Exception('IM SDK 未初始化');
    }

    final result = await _timManager!.sendC2CTextMessage(
      receiver: receiver,
      text: text,
    );

    if (result.code != 0) {
      throw Exception('消息发送失败: ${result.desc}');
    }

    return result.data!;
  }

  /// 获取历史消息
  /// [userId] 对方用户ID
  /// [count] 获取数量（默认15）
  Future<List<V2TIMMessage>> getC2CHistoryMessage({
    required String userId,
    int count = 15,
  }) async {
    if (!_isInitialized || _timManager == null) {
      throw Exception('IM SDK 未初始化');
    }

    final result = await _timManager!.getC2CHistoryMessageList(
      count: count,
      userID: userId,
    );

    if (result.code != 0) {
      throw Exception('获取历史消息失败: ${result.desc}');
    }

    return result.data ?? [];
  }

  /// 添加消息监听
  void addMessageListener(V2TIMMessageListener listener) {
    V2TIMManager.addMessageListener(listener);
  }

  /// 移除消息监听
  void removeMessageListener(V2TIMMessageListener listener) {
    V2TIMManager.removeMessageListener(listener);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add huanxi/lib/services/im_service.dart
git commit -m "feat: 添加 IM 服务封装"
```

---

## Task 5: 前端 IM 页面接入真实 IM

**Files:**
- Modify: `huanxi/lib/modules/im/im_page.dart`

- [ ] **Step 1: 修改 `im_page.dart` 添加 IM 逻辑**

在文件顶部添加导入：

```dart
import '../../services/im_service.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../app/providers/auth_provider.dart';
```

修改 `_ImPageState` 类：

```dart
class _ImPageState extends ConsumerState<ImPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  final IMService _imService = IMService();
  bool _isLoading = false;
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _initIM();
  }

  Future<void> _initIM() async {
    setState(() => _isLoading = true);

    try {
      // 1. 获取 UserSig
      final dio = DioClient.instance;
      final response = await dio.get(ApiEndpoints.imUserSig);
      final usersigData = response['data'];
      final userSig = usersigData['usersig'];
      final expiredTime = usersigData['expired_time'];

      // 2. 获取当前用户ID
      final authState = ref.read(authProvider);
      _myUserId = 'huanxi_${authState.user?.id}';

      // 3. 初始化并登录 IM（如果未初始化）
      if (!_imService.isInitialized) {
        // SDKAppID 需要从配置获取，这里暂时硬编码或从接口获取
        // TODO: 后续可通过接口获取 SDKAppID
        await _imService.init(sdkAppId: 0); // 需要填入真实 SDKAppID
      }
      await _imService.login(userId: _myUserId!, userSig: userSig);

      // 4. 添加消息监听
      _imService.addMessageListener(_messageListener);

      // 5. 加载历史消息
      await _loadHistoryMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('IM 初始化失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 消息监听器
  final _messageListener = V2TIMMessageListener(
    onRecvC2CMessage: (msg) {
      // 收到新消息，添加到列表
      // TODO: 实现消息渲染
    },
  );

  Future<void> _loadHistoryMessages() async {
    try {
      final messages = await _imService.getC2CHistoryMessage(
        userId: widget.userId,
      );
      // 转换为本地消息格式并显示
      // TODO: 实现历史消息渲染
    } catch (e) {
      // 静默失败，使用本地空消息
    }
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    try {
      await _imService.sendTextMessage(
        receiver: widget.userId,
        text: text,
      );

      // 添加到本地列表
      setState(() {
        _messages.add(_ChatMessage(
          content: text,
          isMe: true,
          time: DateTime.now(),
        ));
      });

      _controller.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('消息发送失败: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _imService.removeMessageListener(_messageListener);
    // 不主动登出，保持 IM 连接
    super.dispose();
  }

  // ... 保留原有的 UI 构建代码，仅修改 _sendMessage 调用
}
```

- [ ] **Step 2: Commit**

```bash
git add huanxi/lib/modules/im/im_page.dart
git commit -m "feat: IM 页面接入腾讯 IM"
```

---

## Task 6: 配置文档更新

**Files:**
- Modify: `backend/.env.example` (如存在) 或创建说明

- [ ] **Step 1: 更新 `.env` 配置说明**

在项目文档或 `.env.example` 中添加：

```bash
# 腾讯 IM 配置
IM_SDKAPPID=1400xxxxxx  # 腾讯云 IM 应用 ID
IM_SECRETKEY=xxxxxxxx  # 腾讯云 IM 密钥
```

- [ ] **Step 2: Commit**

```bash
git commit -m "docs: 添加 IM 配置说明"
```

---

## 执行方式

**Plan complete and saved to `docs/superpowers/plans/2026-04-15-tencent-im-plan.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**