# 用户体系重构：AppUser 与 Admin User 分离

**日期**：2026-04-13
**项目**：欢喜 1v1 付费音视频交友
**状态**：设计已确认，待实施

---

## 1. 背景与目标

### 1.1 问题

当前 `User` 表（`backend/app/models/admin.py`）混用了两套职责：
- Admin 后台用户（username + email + password + RBAC）
- App 用户（phone + avatar + balance + app_role）

这导致：
- Admin 账号可以登录 App
- App 用户理论上可以访问 Admin 后台（除非接口加额外校验）
- 用户注册只能靠 Admin 后台手动创建

### 1.2 目标

将 `User` 表拆分为两套独立体系：

| 表 | 用途 | 认证方式 | 注册方式 |
|---|---|---|---|
| `User` | Admin 后台账号 | Admin JWT | Admin 后台创建 |
| `AppUser` | App 用户（普通+主播） | App JWT | App 自助注册 |

---

## 2. 新数据模型

### 2.1 AppUser（新建）

新建 `app/models/app_user.py`：

```python
class AppUser(BaseModel, TimestampMixin):
    """App 用户（普通用户 + 主播）"""
    phone = fields.CharField(max_length=20, unique=True, description="手机号(登录账号)", index=True)
    password = fields.CharField(max_length=128, description="密码(加密)")
    nickname = fields.CharField(max_length=30, null=True, description="昵称")
    avatar = fields.CharField(max_length=500, null=True, description="头像URL")
    gender = fields.CharField(max_length=10, null=True, default="secret", description="male/female/secret")
    balance = fields.IntField(default=0, description="钱包余额(分)")
    status = fields.CharField(max_length=20, null=True, default="normal", description="normal/banned", index=True)
    ban_reason = fields.CharField(max_length=500, null=True, description="封禁原因")
    last_login = fields.DatetimeField(null=True, description="最后登录时间")

    class Meta:
        table = "app_user"
```

### 2.2 Anchor（改造）

改造 `backend/app/models/admin.py` 中的 `Anchor` 模型：

```python
class Anchor(BaseModel, TimestampMixin):
    """主播资料"""
    # 改造：user → app_user，外键指向 AppUser
    app_user = fields.OneToOneField("models.AppUser", related_name="anchor_profile", on_delete=fields.OnDelete.CASCADE)
    is_online = fields.BooleanField(default=False, description="是否在线", index=True)
    call_price = fields.IntField(default=100, description="每分钟通话价格(分)")
    intro = fields.CharField(max_length=500, null=True, description="主播简介")
    tags = fields.JSONField(null=True, description="标签列表")
    avatar = fields.CharField(max_length=500, null=True, description="主播专属头像")
    online_at = fields.DatetimeField(null=True, description="最近上线时间")
    # 新增：申请状态
    apply_status = fields.CharField(max_length=20, default="pending", description="pending/approved/rejected", index=True)
    apply_at = fields.DatetimeField(null=True, description="申请时间")
    reviewed_at = fields.DatetimeField(null=True, description="审核时间")
    reject_reason = fields.CharField(max_length=500, null=True, description="拒绝原因")
```

### 2.3 User 表（精简）

改造 `backend/app/models/admin.py` 中的 `User` 模型：

- **保留字段**：`id`, `username`, `alias`, `email`, `password`, `is_active`, `is_superuser`, `last_login`, `roles`, `dept_id`
- **移除字段**：`avatar`, `gender`, `app_role`, `balance`, `status`, `ban_reason`, `anchor_intro`, `call_price`

### 2.4 业务表（外键迁移）

| 表 | 字段 | 变更 |
|---|---|---|
| `CallRecord` | `caller_id`, `callee_id` | `BigIntField` → 指向 `app_user.id` |
| `GiftRecord` | `sender_id`, `receiver_id` | `BigIntField` → 指向 `app_user.id` |
| `RechargeOrder` | `user_id` | `BigIntField` → 指向 `app_user.id` |
| `WithdrawApply` | `user_id` | `BigIntField` → 指向 `app_user.id` |

> 注意：外键是 `BigIntField` 而非 `ForeignKeyField`，这样不需要在模型层声明关联关系，在接口层通过 `.filter(app_user_id=...)` 查询即可。等效改造，保持代码风格一致。

### 2.5 模型文件结构

```
backend/app/models/
├── __init__.py          # 导出所有模型
├── base.py              # BaseModel, TimestampMixin（不变）
├── enums.py             # 枚举（不变）
├── admin.py             # User, Role, Menu, Api, Anchor, ...
└── app_user.py          # [新建] AppUser
```

---

## 3. 认证体系改造

### 3.1 JWT 策略

两套 JWT 可以共用同一个 `SECRET_KEY`，在 Payload 中加 `is_app: true` 字段区分来源：

```python
class JWTPayload(BaseModel):
    user_id: int
    username: str
    is_superuser: bool = False
    is_app: bool = False        # 新增：App 用户标识
    exp: datetime               # 过期时间
```

- `is_app=True` 的 Token 只能访问 App 端接口（`/api/v1/app/*`）
- `is_app=False` 的 Token 只能访问 Admin 端接口

### 3.2 认证依赖

**新建** `backend/app/core/app_auth.py`：

```python
class AppAuthControl:
    @classmethod
    async def is_app_authed(cls, token: str = Header(..., description="token")) -> "AppUser":
        # 1. 解码 JWT，检查 is_app=True
        # 2. 查 AppUser 表
        # 3. 状态校验（normal/banned）
        # 4. 设置 CTX_APP_USER_ID

DependAppAuth = Depends(AppAuthControl.is_app_authed)
```

**改造** `backend/app/core/dependency.py`：

- `DependAuth`（现有）→ 改名为 `DependAdminAuth`，保持对 `User` 表的认证不变
- `DependAppAuth`（新建）→ 对 `AppUser` 表的认证

### 3.3 路由权限隔离

| 路由前缀 | 认证方式 |
|---|---|
| `/api/v1/app/*` | `DependAppAuth` |
| `/api/v1/user/*` | `DependAdminAuth` |
| `/api/v1/role/*` | `DependAdminAuth` |
| `/api/v1/menu/*` | `DependAdminAuth` |
| `/api/v1/api/*` | `DependAdminAuth` |
| `/api/v1/dept/*` | `DependAdminAuth` |
| `/api/v1/auditlog/*` | `DependAdminAuth` |

---

## 4. API 变更

### 4.1 新增接口

| 接口 | 方法 | 说明 | 认证 |
|---|---|---|---|
| `/app/register` | POST | App 用户注册（手机+验证码+密码） | 无 |
| `/app/anchor/apply` | POST | 用户申请成为主播 | `DependAppAuth` |
| `/app/anchor/apply/status` | GET | 查询申请状态 | `DependAppAuth` |

### 4.2 改造接口（User → AppUser）

| 接口 | 变更说明 |
|---|---|
| `POST /app/login` | 查 `AppUser` 表，生成 `is_app=True` 的 Token |
| `GET /app/user/info` | 查 `AppUser` 表 |
| `GET /app/anchor/list` | 查 `Anchor + AppUser`（改为 JOIN `app_user`） |
| `POST /app/match/random` | 查 `Anchor + AppUser` |
| `POST /app/dialing` | 查 `AppUser` |
| `POST /app/heartbeat` | 查 `AppUser` |
| `POST /app/call/end` | 查 `AppUser` |
| `POST /app/gift/send` | 查 `AppUser` |
| `GET /app/wallet/balance` | 查 `AppUser` |
| `POST /app/recharge/create` | 查 `AppUser` |
| `POST /app/withdraw/apply` | 查 `AppUser` |
| `GET /app/im/usersig` | 查 `AppUser` |
| `GET /app/gift/list` | 无需用户认证，无需变更 |

### 4.3 请求/响应 Schema 新增

```python
# AppRegisterIn
phone: str
code: str           # 验证码（开发期=123456）
password: str

# AppRegisterOut
user_id: int
token: str

# AnchorApplyIn
intro: str           # 申请简介
tags: List[str]     # 擅长领域标签
call_price: int      # 期望通话价格（分/分钟）

# AnchorApplyStatusOut
status: str          # pending/approved/rejected
apply_at: datetime
reject_reason: str
```

---

## 5. Admin 后台扩展

在 vue-fastapi-admin 前端（`web/`）新增两个菜单模块：

### 5.1 App 用户管理

路由：`/app-user`
- 列表：手机号、昵称、性别、余额、状态、注册时间
- 操作：禁用/解禁、查看详情
- 分页、搜索（按手机号/昵称）

### 5.2 主播审批

路由：`/anchor-approval`
- 待审核列表：申请人手机号、简介、期望价格、申请时间
- 操作：审核通过 / 审核拒绝（填拒绝原因）
- 审核通过 → 在 `Anchor` 表创建记录 + `AppUser.is_anchor=True`

> 注意：Admin 后台的接口在 `/api/v1/` 下使用 `DependAdminAuth`，不受影响。但需要在 Admin 后台新增管理页面（前端 Vue）。

---

## 6. Flutter 改动

### 6.1 新增页面

| 页面 | 路由 | 说明 |
|---|---|---|
| 注册页 | `/register` | 手机号 + 验证码 + 密码 |
| 申请主播 | `/anchor-apply` | 填简介 + 期望价格 → 提交申请 |

### 6.2 改造文件

| 文件 | 改造内容 |
|---|---|
| `lib/app/providers/auth_provider.dart` | `AuthState` 改用 `AppUser` 字段 |
| `lib/modules/auth/login_page.dart` | 加「注册账号」入口 |
| `lib/modules/profile/profile_page.dart` | 加「申请成为主播」按钮（未申请/被拒时显示） |
| `lib/modules/profile/edit_profile_page.dart` | 可能需要调整 |
| `lib/core/storage/storage.dart` | 存储结构改为 AppUser |
| `lib/core/constants/api_endpoints.dart` | 新增 `appRegister`、`anchorApply` 等 |

### 6.3 新增 API 端点

```dart
// api_endpoints.dart 新增
static const String appRegister = 'app/register';
static const String anchorApply = 'app/anchor/apply';
static const String anchorApplyStatus = 'app/anchor/apply/status';
```

---

## 7. 数据迁移

**完全重置，不迁移旧数据。**

步骤：
1. 停止后端服务
2. 删除数据库所有相关表（`app_user` 除外，是新建）
3. 删除 `migrations/` 目录下旧的迁移文件
4. 重新 `aerich init-db` 生成新迁移
5. `aerich migrate` + `aerich upgrade` 应用新迁移
6. Admin 后台账号 `admin/123456` 重新创建（通过 `init_superuser()`）
7. 测试 App 用户通过注册接口创建

### 7.1 需要保留的 Admin 数据

- `user` 表中的 admin 账号（admin/123456）
- `role`、`menu`、`api`、`dept` 等表数据（Admin 后台依赖）

### 7.2 需要清空的表

- `anchor`（结构变化，需重建）
- `call_record`
- `gift_record`
- `recharge_order`
- `withdraw_apply`
- `gift`（可以不清，按需保留）

---

## 8. 实施顺序

### 第一阶段：后端核心（改造）
1. 新建 `app/models/app_user.py`
2. 改造 `app/models/admin.py`（精简 User，改造 Anchor）
3. 改造 `app/schemas/app_api.py`（新增 Schema）
4. 改造 `app/schemas/users.py`（移除 app 字段）
5. 改造 `app/core/dependency.py`（新增 `DependAppAuth`）
6. 改造 `app/core/app_auth.py`（新建）
7. 改造 `app/core/ctx.py`（新增 `CTX_APP_USER_ID`）
8. 改造 JWT utils（Payload 加 `is_app`）
9. 改造所有 App 业务接口（改 User → AppUser）
10. 新增注册接口 `app/api/v1/app/register.py`
11. 新增主播申请接口 `app/api/v1/app/anchor_apply.py`
12. 更新路由注册（`app/api/v1/app/__init__.py`）
13. 数据库迁移 + 验证

### 第二阶段：Admin 后台（前端 Vue）
14. Admin 后台新增 App 用户管理页面
15. Admin 后台新增主播审批页面

### 第三阶段：Flutter 改造
16. 新增注册页
17. 改造 `auth_provider.dart`
18. 新增主播申请流程
19. `flutter analyze` 检查
20. 重新构建 APK

---

## 9. 验收标准

- [ ] App 用户可以注册、登录
- [ ] 登录后 Token 可以访问所有 `/app/*` 接口
- [ ] Admin 账号（admin/123456）不能登录 App
- [ ] Admin 后台（web/）可以正常管理 admin 用户
- [ ] 用户可以申请成为主播，Admin 后台可以审批
- [ ] 审批通过后，用户在主播列表中可见
- [ ] `flutter analyze` 零问题
- [ ] Debug APK 正常构建

---

**设计版本**：V1.0
**状态**：已确认，待实施
