# 欢喜 (Huanxi) Flutter 跨端开发设计文档

**日期**：2026-04-11  
**项目**：1v1 付费音视频交友平台  
**技术栈**：Flutter 3.22+ + Riverpod + Dio + go_router  
**目标平台**：iOS + Android  
**后端**：基于 [vue-fastapi-admin](https://github.com/mizhexiaoxiao/vue-fastapi-admin) 二次开发（Python 3.11 + FastAPI + Tortoise ORM + Pydantic v2 + JWT + Redis + MySQL 8.0），单机单实例部署

> 后端以 vue-fastapi-admin 为基础框架，复用其用户管理、RBAC 权限、菜单管理、JWT 认证等模块；在 `app/api` 下新增 `/app/...` 业务接口（主播管理、速配、通话计费、礼物、钱包充值等）。

---

## 1. 整体架构

```
┌─────────────────────────────────────────────────┐
│                 UI Layer (Riverpod)              │
│  Pages: Login, Home, Call, Profile, Recharge... │
├─────────────────────────────────────────────────┤
│              Business Logic Layer                │
│  AuthService, CallService, GiftService...       │
├─────────────────────────────────────────────────┤
│              Repository Layer                    │
│  HTTP (Dio) / WebSocket / IM / RTC              │
├─────────────────────────────────────────────────┤
│              SDK Integration                     │
│  Flutter 插件 + 原生 SDK (MethodChannel)         │
└─────────────────────────────────────────────────┘
```

### 1.1 状态管理：Riverpod
- 使用 `riverpod` + `riverpod_generator` 生成 Provider
- 结合 `state_notifier` 管理复杂状态

### 1.2 网络请求：Dio
- 统一拦截器处理 Token、签名、错误码
- 错误码全局处理：401→跳转登录、403→封禁弹窗、501→拉起充值

### 1.3 路由：go_router
- 声明式路由，支持深链接

---

## 2. 核心功能模块

| 模块 | 优先级 | 说明 |
|------|--------|------|
| 启动与鉴权 | P0 | Splash、SDK 初始化、登录态检查 |
| 登录 | P0 | 手机号+验证码（开发期账号密码），用户协议 |
| 首页 | P0 | 主播瀑布流、在线状态、一键速配、底部导航 |
| 通话 | P0 | 呼叫等待/接听、实时计费心跳、美颜、挂断 |
| 礼物 | P0 | 礼物面板、发送、SVGA 动画队列 |
| 个人中心 | P0 | 资料编辑、钱包余额、充值、提现绑定 |
| IM | P1 | 图文/语音消息、自定义卡片 |
| 设置 | P1 | 防骚扰、黑名单、青少年模式 |

---

## 3. 后端 API 设计

### 3.1 统一响应格式
```json
{
  "code": 200,
  "msg": "success",
  "data": {},
  "rows": [],
  "current": 1,
  "total": 0,
  "has_more": false
}
```

### 3.2 核心接口

| 模块 | 接口 | 方法 | 说明 |
|------|------|------|------|
| 用户 | /app/login | POST | 手机号+验证码登录 |
| 用户 | /app/user/info | GET | 获取用户信息 |
| 首页 | /app/anchor/list | GET | 主播推荐列表（分页） |
| 首页 | /app/match/random | POST | 一键速配 |
| 通话 | /app/dialing | POST | 发起呼叫（余额预检） |
| 通话 | /app/heartbeat | POST | 每5秒心跳上报 |
| 通话 | /app/call/end | POST | 通话结束结算 |
| 礼物 | /app/gift/list | GET | 礼物列表 |
| 礼物 | /app/gift/send | POST | 发送礼物 |
| 钱包 | /app/wallet/balance | GET | 余额查询 |
| 钱包 | /app/recharge/create | POST | 创建充值订单 |
| 钱包 | /app/withdraw/apply | POST | 申请提现 |
| IM | /app/im/usersig | GET | 获取 IM UserSig |

### 3.3 错误码
| Code | 含义 | 客户端处理 |
|------|------|-----------|
| 200 | 成功 | 正常解析 |
| 401 | Token 失效 | 清空本地数据，跳转登录 |
| 403 | 账号封禁 | 弹窗显示原因，退回登录 |
| 501 | 余额不足 | 拉起充值面板 |

---

## 4. SDK 集成方案

由于部分 SDK 没有纯 Flutter 实现，采用 **Flutter 插件 + 原生 SDK (MethodChannel)** 混合方案：

| 功能 | SDK | 集成方式 |
|------|-----|----------|
| RTC | Agora / Zego | 原生 SDK + MethodChannel |
| IM | 腾讯云 IM | 原生 SDK + MethodChannel |
| 美颜 | FaceUnity + FBAgoraLiveFlutter | 原生 SDK + Flutter 插件 |
| 礼物动画 | SVGA | svgaplayer_flutter 插件 |
| 微信支付 | 微信 OpenSDK | fluwx 插件 |
| 支付宝 | Alipay SDK | sy_flutter_alipay 插件 |

> **注意**：友盟统计、Bugly 崩溃监控、openinstall 渠道追踪暂不集成，留待正式上线前按需引入。

---

## 5. 数据存储

| 类型 | 方案 | 用途 |
|------|------|------|
| 键值对 | shared_preferences | Token、用户ID、开关状态 |
| 结构化 | hive | 用户信息缓存、礼物列表缓存 |

---

## 6. 关键业务流程

### 6.1 登录流程
1. 输入手机号 → 获取验证码（滑块验证）
2. 输入验证码 → 调用登录接口
3. 成功 → 保存 Token → 获取 UserSig → 登录 IM → 跳转首页

### 6.2 通话计费流程
1. 发起呼叫前 → 调用 `/app/dialing` 预检余额
2. 接通后 → 客户端启动 5 秒定时器 → 发送 `/app/heartbeat`
3. 服务端 → Redis 预扣费，返回剩余余额
4. 余额不足 → 返回 501 → 客户端拉起充值面板
5. 挂断 → 调用 `/app/call/end` → 服务端异步写 MySQL 账单

### 6.3 礼物发送流程
1. 点击礼物 → 调用 `/app/gift/send`
2. 成功 → 通过 IM 下发自定义信令
3. 接收方 → 解析信令 → SVGA 播放动画
4. 连续礼物 → 队列播放（防 OOM）

---

## 7. 非功能性需求

### 7.1 性能
- RTC 延迟 < 400ms
- 首帧出图 < 1000ms
- 礼物动画防 OOM（队列 + 单播放器）

### 7.2 安全
- 接口签名防重放（Sign + 时间戳）
- 敏感接口 AES 加密
- 域名动态下发（防 DNS 污染）

### 7.3 保活
- Android：集成厂商推送（华为、小米、OPPO、VIVO）
- iOS：APNs 推送
- 长连接：IM 自带 WebSocket 保活

---

## 8. 开发环境

### Flutter 端
```yaml
environment:
  sdk: ">=3.4.0 <4.0.0"
  flutter: ">=3.22.0"

dependencies:
  flutter:
    sdk: flutter
  riverpod: ^2.5.0
  riverpod_generator: ^2.4.0
  dio: ^5.4.0
  go_router: ^14.0.0
  shared_preferences: ^2.2.0
  hive: ^2.2.0
  svgaplayer_flutter: ^2.1.0
  fluwx: ^5.1.0
  sy_flutter_alipay: ^2.0.0
```

### 后端（vue-fastapi-admin 二次开发）
- Python 3.11+
- FastAPI + Tortoise ORM + Pydantic v2
- MySQL 8.0 + Redis
- JWT 认证

> 友盟统计、Bugly 崩溃监控、openinstall 渠道追踪暂不引入，留待正式上线前按需集成。

---

## 9. 项目结构

```
backend/                  # 后端 (vue-fastapi-admin 二次开发)
├── app/
│   ├── api/              # 业务接口 (/app/...)
│   ├── api/admin/        # 管理后台接口 (复用)
│   ├── controllers/      # 控制器
│   ├── models/           # Tortoise ORM 模型
│   └── schemas/          # Pydantic 请求/响应模型
├── web/                  # 前端管理后台 (复用)
├── migrations/           # 数据库迁移
└── run.py                # 启动入口

lib/
├── main.dart
├── app/
│   ├── providers/          # Riverpod providers
│   ├── routes/             # go_router 配置
│   └── theme/              # 主题配置
├── core/
│   ├── constants/          # 常量、错误码
│   ├── utils/              # 工具类
│   ├── storage/            # 本地存储
│   └── network/            # Dio 配置、拦截器
├── modules/
│   ├── auth/               # 登录模块
│   ├── home/               # 首页模块
│   ├── call/               # 通话模块
│   ├── gift/               # 礼物模块
│   ├── profile/            # 个人中心
│   ├── im/                 # IM 模块
│   └── settings/           # 设置模块
└── services/               # 业务服务层
```

---

**文档版本**：V1.1
**状态**：已确认，待进入实施计划阶段
