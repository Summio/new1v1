# 欢喜 (Huanxi) 1v1 付费音视频交友 — 开发计划

> 基于 `2026-04-11-huanxi-flutter-design.md` 设计文档追踪开发进度

---

## 项目概览

- **技术栈**：Flutter 3.22+ / Riverpod / Dio / go_router + FastAPI + Tortoise ORM + MySQL + Redis
- **后端**：vue-fastapi-admin 二次开发，单机部署
- **状态**：核心功能可用，APK 可构建并运行

---

## 一、已完成 ✅

### 1.1 后端基础设施
- [x] MySQL 数据库 + Tortoise ORM 模型
- [x] Redis 连接与缓存
- [x] JWT 认证（Token 生成/验证）
- [x] 统一响应格式（`Success` / `Fail` / `SuccessExtra`）
- [x] 用户、角色、菜单、API 管理系统（RBAC）
- [x] 管理后台初始化数据（超管账号 `admin/123456`）

### 1.2 后端业务 API（`/api/v1/app/`）
- [x] `/app/login` — 手机号 + 密码/验证码登录
- [x] `/app/user/info` — 获取当前用户信息
- [x] `/app/anchor/list` — 主播推荐列表（分页）
- [x] `/app/match/random` — 一键速配
- [x] `/app/dialing` — 发起呼叫（余额预检）
- [x] `/app/heartbeat` — 通话心跳（5秒/次，Redis 扣费）
- [x] `/app/call/end` — 通话结束结算
- [x] `/app/gift/list` — 礼物列表查询
- [x] `/app/gift/send` — 发送礼物（扣费 + 记录）
- [x] `/app/wallet/balance` — 余额查询
- [x] `/app/recharge/create` — 创建充值订单（Mock）
- [x] `/app/withdraw/apply` — 申请提现
- [x] `/app/im/usersig` — 获取 IM UserSig（Mock）

### 1.3 Flutter 脚手架
- [x] 项目创建 + `pubspec.yaml` 依赖配置
- [x] Riverpod 状态管理框架
- [x] Dio 网络层（统一拦截器、错误处理）
- [x] go_router 路由配置
- [x] 本地存储（Hive + shared_preferences）
- [x] 主题配置（AppTheme）
- [x] `flutter analyze` 零警告/零错误

### 1.4 Flutter 核心页面
- [x] Splash 启动页
- [x] 登录页（手机号 + 密码/验证码）
- [x] 首页（底部导航、主播列表、分类筛选）
- [x] 一键速配入口
- [x] 通话房间页（呼叫等待、时长计时、控制栏）
- [x] 礼物面板 UI
- [x] 个人资料页
- [x] 充值页面 UI
- [x] 设置页
- [x] 编辑资料页

### 1.5 构建
- [x] Debug APK 成功构建并可运行
- [x] Android 阿里云镜像配置（Gradle 依赖）
- [x] Gradle 代理配置（verge-mihomo 7897）

---

## 二、开发中 🚧

### 2.1 礼物面板对接后端
**文件**: `lib/modules/gift/gift_panel.dart`
**依赖后端**: `/app/gift/list`（已有），`/app/gift/send`（已有）
- [ ] 调用 `/app/gift/list` 获取礼物列表
- [ ] 礼物卡片显示图标（网络图片）、名称、价格
- [ ] 点击发送 → 调用 `/app/gift/send` → 扣余额
- [ ] 发送成功 → 余额同步更新 → 播放简单动画
- [ ] 余额不足（501）→ 引导充值

### 2.2 个人资料 + 充值 UI 对接
**文件**: `lib/modules/profile/recharge_page.dart`
**依赖后端**: `/app/wallet/balance`（已有），`/app/recharge/create`（Mock）
- [ ] 进入充值页 → 调用 `/app/wallet/balance` 获取余额
- [ ] 选择充值档位 → 调用 `/app/recharge/create` 创建订单
- [ ] 微信/支付宝扫码支付（见「支付集成」）
- [ ] 支付回调 → 刷新余额

---

## 三、待开发 📋

### 3.1 视频通话 WebRTC 集成 🔴 高优先级
**文件**: `lib/modules/call/call_room_page.dart`
**依赖后端**: `/app/dialing`、`/app/heartbeat`、`/app/call/end`（已有信令）

当前状态：通话房间 UI 已完成，但通话本身是模拟的（没有真实音视频）。

待实现：
- [ ] 引入 `flutter_webrtc` 包
- [ ] 实现 WebRTC 信令交换（通过后端 `/app/dialing` 接口交换 SDP/ICE）
- [ ] 通话房间：本地预览 + 远端画面渲染
- [ ] 主播端接听/拒绝逻辑（需要主播端 App 或 Web 页面）
- [ ] 通话断开（网络差/主动挂断/余额不足）处理
- [ ] 前后台切换时通话保持

### 3.2 腾讯 IM 集成 🟡 中优先级
**文件**: `lib/modules/im/`、`lib/services/`
**依赖后端**: `/app/im/usersig`（目前返回 Mock）

当前状态：IM 页面是占位符。

待实现：
- [ ] 生成真实 UserSig（需腾讯云账号 + 私钥）
- [ ] 引入 `tim_ui_kit` 或原生腾讯 IM SDK
- [ ] 登录时初始化 IM 并监听消息
- [ ] 通话邀请信令下发（IM 自定义消息）
- [ ] 礼物通知信令（IM 自定义消息）
- [ ] 未读消息角标 + 会话列表

### 3.3 支付集成 🟡 中优先级
**文件**: `backend/app/api/v1/app/wallet.py`
**依赖前端**: `lib/modules/profile/recharge_page.dart`

当前状态：后端 `/app/recharge/create` 返回模拟 `pay_url`。

待实现：
- [ ] 微信支付统一下单接口接入
- [ ] 支付宝当面付接口接入
- [ ] 支付回调通知处理（`/api/v1/app/wallet/callback`）
- [ ] 订单状态轮询 + 成功弹窗
- [ ] Flutter 端：微信 OpenSDK / 支付宝 SDK 拉起支付

### 3.4 用户注册流程 🟢 低优先级
**依赖**: 后端新增 `/app/register` 接口 + Flutter 新增注册页

当前状态：用户只能由管理员预创建（admin 后台）。

待实现：
- [ ] 后端：`/app/register` 手机号 + 验证码注册
- [ ] 验证码发送（可复用登录验证码逻辑）
- [ ] Flutter 注册页（手机号 → 获取验证码 → 设置密码 → 注册成功）
- [ ] 注册完成后自动登录

### 3.5 主播端管理 🟢 低优先级
**依赖**: 后端已有 Anchor 模型，Flutter 新增主播端入口

当前状态：Anchor 模型已创建，数据需通过 admin 后台录入。

待实现：
- [ ] 主播端 App 入口（区分用户角色 `app_role: anchor`）
- [ ] 主播在线/离线状态切换
- [ ] 主播端：查看累计收益、提现记录
- [ ] 主播端：设置通话单价、简介、标签
- [ ] 主播个人主页展示（用户端看主播详情）

### 3.6 App 补充页面 🟢 低优先级
**文件**: `lib/modules/` 下的空模块

当前状态：部分页面有占位符但未完整实现。

待实现：
- [ ] 用户注册页面
- [ ] 用户协议页面（`/app/agreement`）
- [ ] 隐私政策页面（`/app/privacy`）
- [ ] 密码修改页面
- [ ] 消息通知列表页
- [ ] 意见反馈页

---

## 四、已知限制 ⚠️

1. **主播端**：目前无主播端 App，Anchor 数据需通过 admin 后台录入。用户呼叫主播时，主播通过 Web 或独立 App 接听。
2. **支付**：微信/支付宝支付为 Mock，生产环境需申请商户号并完成签约。
3. **IM**：UserSig 为 Mock，生产环境需接入腾讯云 IM SDK 并配置私钥。
4. **美颜**：未集成美颜 SDK，视频通话为原始画面。
5. **推送**：未集成厂商推送（华为/小米/OPPO/VIVO），iOS APNs 未配置。

---

## 五、测试账号

| 角色 | 手机号 | 密码/验证码 |
|------|--------|------------|
| 用户 | `13800138000` | `123456`（验证码）|
| 用户 | `13900139000` | `123456`（密码）|
| 主播 | `15000150001` | `123456`（密码）|

> 主播数据需在 admin 后台（`http://server:9999/docs`）手动创建并设置 `app_role=anchor`

---

**最后更新**：2026-04-13
**文档版本**：V1.2
