# 腾讯 IM 接入设计方案

**日期**：2026-04-15
**主题**：基础单聊功能接入腾讯云 IM

---

## 1. 需求概述

- **功能**：基础单聊（文字/图片消息）
- **消息存储**：服务端漫游（跨设备同步）
- **离线推送**：暂不需要
- **配置方式**：后台环境变量可配置

---

## 2. 架构概览

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Flutter    │────▶│  后端 API   │────▶│  腾讯 IM   │
│  App        │     │  (UserSig) │     │  云端      │
└─────────────┘     └─────────────┘     └─────────────┘
       │                                      │
       ▼                                      ▼
  本地消息缓存                          消息同步/漫游
```

---

## 3. 后端改动

### 3.1 配置文件 `app/settings/im.py`

新增腾讯 IM 配置，支持环境变量：

```python
class IMSettings(BaseSettings):
    model_config = {"env_file": ".env", "extra": "ignore"}

    # 腾讯 IM 配置（生产环境必填）
    IM_SDKAPPID: int = 0
    IM_SECRETKEY: str = ""
```

环境变量：
```bash
IM_SDKAPPID=你的SDKAppID
IM_SECRETKEY=你的SecretKey
```

### 3.2 UserSig 生成 `app/api/v1/app/im.py`

替换 Mock 实现，使用腾讯 `TLSSigAPIv2` 生成真实签名：

```python
from tencentcloud.imsig.v2 import TLSSigAPIv2

@router.get("/im/usersig", summary="获取IM UserSig", dependencies=[DependAppAuth])
async def get_usersig():
    user_id = CTX_APP_USER_ID.get()
    api = TLSSigAPIv2(settings.IM_SDKAPPID, settings.IM_SECRETKEY)
    usersig = api.generate_user_sig(
        userid=f"huanxi_{user_id}",  # 前缀避免与其他业务冲突
        expire=3600 * 24 * 7  # 7天有效期
    )
    expired_time = int(time.time()) + 3600 * 24 * 7
    return Success(data=IMSigOut(usersig=usersig, expired_time=expired_time))
```

---

## 4. 前端改动

### 4.1 添加依赖 `pubspec.yaml`

```yaml
dependencies:
  # 腾讯 IM Flutter SDK（版本需根据 pub.dev 最新版确定）
  # 执行: flutter pub add tencentcloud_im_sdk
  tencentcloud_im_sdk: ^版本号
```

### 4.2 IM 服务 `lib/services/im_service.dart`

```dart
class IMService {
  static final IMService _instance = IMService._();
  factory IMService() => _instance;

  V2TIMManager? _timManager;

  /// 初始化 IM SDK
  Future<void> init(String sdkAppId) async {
    _timManager = TIMManager.getInstance();
    await _timManager.init(
      appId: int.parse(sdkAppId),
      logLevel: LogLevel.logLevelVerbose,
    );
  }

  /// 登录 IM
  Future<void> login({
    required String userID,
    required String userSig,
  }) async {
    final res = await _timManager!.login(
      userID: userID,
      userSig: userSig,
    );
    if (res.code != 0) throw Exception(res.msg);
  }

  /// 发送消息
  Future<V2TimMessage> sendMessage({
    required String receiver,
    required String content,
  }) async {
    final msg = await _timManager!.sendMessage(
      receiver: receiver,
      message: Message(text: TextElem(content)),
    );
    return msg;
  }

  /// 消息监听
  void addListener(V2TimMsgListener listener) {
    _timManager!.addSimpleMsgListener(listener);
  }
}
```

### 4.3 API 端点追加

在 `api_endpoints.dart` 中追加（如果需要其他 IM 相关接口）。

---

## 5. 数据流

```
1. App 启动 → 请求后端 /app/im/usersig 获取真实签名
2. 使用 UserSig 初始化腾讯 IM SDK
3. 登录 IM 成功 → 进入聊天页面
4. 发送消息 → 腾讯 IM 云端 → 对方接收
5. 消息自动同步到服务端（漫游）
```

---

## 6. 实现方案对比

| 方案 | 优点 | 缺点 |
|------|------|------|
| **A. 后端生成 UserSig** | 密钥安全、可控签名有效期 | 后端多一次调用 |
| **B. 前端生成 UserSig** | 减少后端调用 | 密钥暴露在前端（不推荐） |

**采用方案 A**：后端生成 UserSig，前端仅做 IM 展示和收发。

---

## 7. 待配置项

| 项 | 配置位置 | 说明 |
|---|---------|------|
| IM_SDKAPPID | `.env` | 腾讯云 IM 应用 ID |
| IM_SECRETKEY | `.env` | 腾讯云 IM 密钥 |

---

## 8. 测试要点

- [ ] 后端生成 UserSig 有效（可使用腾讯官方校验工具验证）
- [ ] 前端 IM 登录成功
- [ ] 单聊消息收发正常
- [ ] 消息漫游可跨设备查看
- [ ] 配置缺失时优雅报错
