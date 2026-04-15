# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

**欢喜 (Huanxi)** — 1v1 付费视频交友平台，包含 Flutter App（前端）和 FastAPI 服务（后端）。

- **Flutter SDK**: `D:\Program Files\Android\flutter`
- **后端入口**: `backend/run.py` → uvicorn 加载 `app:app`（即 `backend/app/__init__.py` 中的 FastAPI 实例）
- **MySQL**: `localhost:3306`，数据库名 `huanxi`，账号 `root/123456`
- **后端 API 基础**: `http://192.168.100.199:9999/api/v1/`

---

## 目录结构

```
D:\1v1\new1v1\
├── huanxi/                    # Flutter App
│   ├── lib/
│   │   ├── main.dart          # App 入口
│   │   ├── app/               # 路由(go_router)、主题、Provider
│   │   ├── core/              # 网络(Dio)、存储(Hive/SP)、常量
│   │   ├── modules/            # 业务模块页面
│   │   └── services/           # 业务服务层
│   └── superpowers/            # Claude Code 技能文件
│
├── backend/
│   ├── app/
│   │   ├── __init__.py        # FastAPI 应用实例 (app:app)
│   │   ├── api/v1/            # API 路由 (含 apis/ 管理端 + app/ App端)
│   │   ├── core/               # 中间件、异常、Redis、初始化
│   │   ├── models/             # Tortoise ORM 模型
│   │   ├── schemas/            # Pydantic Schemas
│   │   └── settings/            # 配置 (config.py, database.py, trtc.py, im.py)
│   └── migrations/models/       # Aerich 迁移版本记录
│
├── docs/                       # 项目文档（含设计稿、设计规范）
├── TODO.md                     # 开发进度追踪
└── CLAUDE.md
```

---

## 开发命令

### Flutter

```bash
cd D:/1v1/new1v1/huanxi

flutter analyze          # 代码分析（提交前必跑）
flutter pub get          # 获取依赖
flutter clean && flutter build apk --debug   # 清理后构建
flutter run              # 调试运行
```

### 后端

```bash
cd D:/1v1/new1v1/backend

# 启动后端（自动加载 .env 配置）
python run.py

# 代码检查（需安装依赖）
black ./ --check
isort ./ --profile black --check
ruff check ./app

# 代码格式化
black ./
isort ./ --profile black

# 数据库迁移
aerich migrate --name <描述性名称>
aerich upgrade
```

### 环境变量配置

后端使用 `backend/.env` 文件配置本地开发环境（已加入 `.gitignore`）：

```bash
# 调试模式（本地开发必须设为 true，否则启动失败）
DEBUG=true

# 生产环境必须设置：
# SECRET_KEY=your-cryptographically-strong-key
# DB_PASSWORD=your-secure-db-password
# ADMIN_PASSWORD=your-admin-password
# CORS_ORIGINS=https://your-domain.com
```

### 数据库迁移规范

**所有表结构变更必须通过 aerich 迁移，禁止直接操作数据库。**

```bash
cd D:/1v1/new1v1/backend
aerich migrate --name <描述性名称>
aerich upgrade
```

---

## 架构要点

### 后端 API 分为两套

- **`/api/v1/apis/*`** — 管理后台 API（admin 端，菜单/角色/用户管理）
- **`/api/v1/app/*`** — App 端 API（登录、通话、礼物、充值、IM 等）

App 端所有接口均需 `Authorization: Bearer <token>` 认证。

### 响应格式

```json
{ "code": 200, "msg": "success", "data": { ... } }
```

| code | 含义 |
|------|------|
| 200 | 成功 |
| 401 | Token 失效 |
| 403 | 账号封禁（含 ban_reason） |
| 501 | 余额不足 |

### 前端状态管理

- **Riverpod** — 状态管理（`lib/app/providers/`）
- **go_router** — 路由（`lib/app/routes/app_router.dart`）
- **Dio** — 网络请求（`lib/core/network/dio_client.dart`），拦截器自动注入 Token 并处理 401/403/501
- **Hive + SharedPreferences** — 本地存储（`lib/core/storage/storage.dart`）

### 第三方服务配置

| 服务 | 配置位置 |
|------|----------|
| Tencent TRTC | `backend/app/settings/trtc.py` |
| Tencent IM | `backend/app/settings/im.py` |
| MySQL | `backend/app/settings/config.py` (TORTOISE_ORM) |

---

## 安全修复记录

### 已完成的修复

1. **配置安全强化** (`app/settings/config.py`)
   - `DEBUG` 默认 `False`，生产环境必须通过环境变量开启
   - `SECRET_KEY` / `DB_PASSWORD` 非 DEBUG 模式未配置则启动失败
   - `CORS_ORIGINS` 默认空列表，生产环境必须显式配置
   - Redis 密码空字符串正确处理为 `None`

2. **认证与授权** (`app/core/dependency.py`)
   - 新增 `RateLimit` 类，基于 Redis 滑动窗口限流
   - 登录：每分钟 10 次
   - 注册：每 5 分钟 5 次
   - 心跳：每分钟 20 次
   - 支付回调：每分钟 10 次
   - Redis 故障时优雅降级（放行请求）

3. **输入验证加强** (`app/schemas/app_user.py`, `app/schemas/app_api.py`)
   - 手机号：中国格式正则验证（支持 +86/00 前缀）
   - 密码：至少 8 位且同时包含字母和数字
   - 银行卡号：10-23 位

4. **通话计费修复** (`app/api/v1/app/call.py`)
   - `CallRecord` 新增 `call_price` 字段，锁定通话单价
   - 心跳时长原子更新，防止并发错误
   - 心跳间隔从配置读取（`settings.HEARTBEAT_INTERVAL`）

5. **其他修复**
   - 隐私政策/用户协议改为公开访问（移除认证）
   - 腾讯云 IM 签名增加 DEPRECATED 警告
   - 审计日志中间件修复空异常吞没问题
   - CRUD 基类增加 `DoesNotExist` 异常处理
   - 用户列表 N+1 查询优化（批量查部门）
   - 菜单列表递归 N+1 优化（内存构建树）
   - 账单明细加载上限控制（每表最多 500 条）

### 待接入的真实服务

- **支付网关**：微信支付/支付宝（当前 `wallet/callback` 为 Mock）
- **腾讯云 IM**：真实 UserSig 生成（当前 `im/usersig` 为 Mock）

---

## 代码约定

- **Flutter**: Riverpod / go_router / null-aware spread (`...?`) / super parameters
- **后端**: black + isort 格式化，ruff 检查；Tortoise ORM 模型 + Pydantic Schemas
- `context.pop()` 不可用时使用 `Navigator.pop(context)`（需 import go_router）
- Switch `activeColor` 已废弃，用 `activeThumbColor`

---

## 重要参考

- **开发进度**: `TODO.md` — 追踪已完成/进行中/待开发功能
- **业务错误码**: 前端 `lib/core/network/api_interceptor.dart` 统一处理 401/403/501
- **登录路由**: `/login`；充值路由: `/profile/recharge`（401/501 时的跳转目标）
