# AGENTS.md

本文件用于指导在本仓库中执行开发任务的智能体与协作者。
最后更新：2026-05-07

## 项目概述

**欢喜 (Huanxi)**：1v1 付费音视频交友平台。
当前仓库主要包含四部分：

- `huanxi/`：Flutter 客户端（用户端）
- `backend/`：FastAPI 后端服务（含 App API 与管理 API）
- `backend/web/`：Vue3 管理后台前端
- `face_beauty_sdk/`：美颜 SDK 与示例工程（联调参考）

## 当前项目状态（以仓库现状为准）

- 核心链路已具备：登录、推荐、速配、呼叫、通话心跳计费、礼物、钱包、提现申请、充值配置。
- Flutter 端基础框架已完成：Riverpod + Dio + go_router + 本地存储。
- 后端 App API 已实现主要业务接口，管理端 RBAC 能力可用。
- 持续完善方向：
  - 礼物面板与后端完整联动
  - 充值页与余额/下单联动
- 尚未落地真实能力（仍需外部服务打通）：
  - WebRTC 实时音视频
  - 腾讯 IM 真实 UserSig 与消息链路
  - 微信/支付宝真实支付网关

进度与设计记录请查看 `docs/`（如 `docs/reports/`、`docs/superpowers/specs/`、`docs/superpowers/plans/`）。

## 目录结构（当前）

```text
D:/1v1/new1v1/
├── AGENTS.md
├── docs/
├── face_beauty_sdk/
├── huanxi/                  # Flutter App
│   ├── lib/
│   ├── assets/
│   ├── test/
│   └── pubspec.yaml
└── backend/                 # FastAPI + Admin
    ├── app/
    ├── migrations/
    ├── scripts/
    ├── tests/
    ├── web/                 # Vue3 管理后台
    ├── run.py
    ├── pyproject.toml
    └── requirements.txt
```

## 关键入口与环境

- Flutter 入口：`huanxi/lib/main.dart`
- Flutter API 地址必须通过 `--dart-define=API_BASE_URL=...` 显式传入；客户端禁止内置 debug/profile/release 默认后端地址。
- 后端入口：`backend/run.py`（加载 `app:app`，默认端口 `9999`）
- 本地数据库默认：MySQL `localhost:3306`，数据库 `huanxi`（见 `backend/app/settings/config.py`）
- 后端配置：`backend/.env`（参考 `backend/.env.example`）

## 常用开发命令

### Flutter

```bash
cd D:/1v1/new1v1/huanxi
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://<host>:9999/api/v1/
flutter build apk --debug --dart-define=API_BASE_URL=http://<host>:9999/api/v1/
```

### 后端（API）

```bash
cd D:/1v1/new1v1/backend
python run.py
ruff check ./app
black ./ --check
isort ./ --profile black --check
pytest -vv -s --cache-clear ./
```

### 后端（迁移）

```bash
cd D:/1v1/new1v1/backend
aerich migrate --name <desc>
aerich upgrade
```

### 管理后台前端（Vue）

```bash
cd D:/1v1/new1v1/backend/web
pnpm i   # 或 npm i
pnpm dev # 或 npm run dev
pnpm build
pnpm lint
```

## API 分层约定

- `/api/v1/apis/*`：管理后台 API
- `/api/v1/app/*`：App 业务 API

App 端接口默认使用 `Authorization: Bearer <token>`。

## 响应与错误码约定

统一响应风格：成功/失败 + `code/msg/data` 结构。
重点业务码（当前前端已处理）：

- `200`：成功
- `401`：未认证或登录失效
- `403`：账号封禁/无权限
- `501`：余额不足

## 开发约束

- 优先保持现有行为稳定，不做无关改动。
- `huanxi` 客户端不得为 `API_BASE_URL` 设置任何默认兜底地址；本地、测试、生产都必须由构建命令或环境配置显式传入。
- 涉及表结构变更时，必须走 Aerich 迁移，禁止直接改库。
- 生产配置不得依赖默认弱口令，敏感配置必须走环境变量。
- 新增功能时，同步评估对通话计费、鉴权、余额扣减链路的影响。
- 开发原则：所有能够由后端实现或配置的信息，均应从后端获取或在后端实现；前端仅做展示与交互，不固化业务配置与业务规则。

## 功能模块说明

### 充值配置系统

运营人员可通过管理后台动态配置充值套餐，配置通过后端接口下发给客户端。

**核心文件：**
- 后端 Schema：`backend/app/schemas/system.py`
- 后端接口：`backend/app/api/v1/apis/system/recharge_config.py`
- 管理后台页面：`backend/web/src/views/system/recharge-config/index.vue`
- 数据存储：`system_config` 表，配置项 `recharge_packages`（JSON 格式）

**接口说明：**
- `GET /api/v1/apis/system/recharge-config`：获取充值配置（需管理员权限）
- `PUT /api/v1/apis/system/recharge-config`：更新充值配置（需管理员权限）
- `GET /api/v1/app/init/bootstrap`：客户端启动接口，返回 `recharge_packages` 字段

**数据格式：**
```json
{
  "packages": [
    {
      "amount": 600,
      "coins": 600,
      "label": "6元",
      "tag": "尝鲜"
    }
  ]
}
```

**注意事项：**
- `amount` 和 `coins` 单位均为分（int），前端显示时需转换为元
- 配置变更后 Redis 缓存自动清除，60秒内生效
- 客户端应实现默认套餐兜底，防止配置异常时无法充值

## 任务执行建议

- 修改前先确认影响范围（前端页面、后端接口、数据模型）。
- 修改后至少完成对应侧检查（Flutter analyze / 后端 lint / 后端 tests）。
- 涉及支付、IM、通话链路时，优先给出降级方案与回滚点。
