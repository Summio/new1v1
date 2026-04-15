# 后端代码审查修复计划

**日期**: 2026-04-13
**状态**: 草稿
**范围**: 欢喜 (Huanxi) 1v1 视频交友 App 后端

---

## 背景

对后端代码进行全面审查后，发现 19 个问题，分布在安全、计费、配置、代码质量四个维度。本文档记录修复方案。

---

## 问题清单

### Critical（必须修复）

| # | 问题 | 文件 | 说明 |
|---|------|------|------|
| 1 | 管理员 API 缺少权限校验 | `app/api/v1/users/users.py`, `app/api/v1/apis/apis.py` | `/create`, `/update`, `/delete` 无 `DependPermission` |
| 2 | 审计日志无法记录 App 用户 | `app/core/middlewares.py` | 中间件只查询 `User` 表，App 用户始终 user_id=0 |
| 3 | 通话双重计费 | `app/api/v1/app/call.py` | `dialing()` 已预扣一次，`heartbeat()` 每5秒又扣，实际扣了13次 |
| 4 | 提现直接扣余额无冻结 | `app/api/v1/app/wallet.py` | 审核拒绝后钱无法退回 |
| 5 | Redis/DB 余额不同步 | `app/api/v1/app/call.py` | 结算时非原子操作，可能产生偏差 |

### High（重要）

| # | 问题 | 文件 | 说明 |
|---|------|------|------|
| 6 | JWT Secret Key 硬编码 | `app/settings/config.py` | `SECRET_KEY` 硬编码，应从环境变量读取 |
| 7 | `_deduct_balance` 死代码 | `app/api/v1/app/call.py` | 函数定义后从未调用 |
| 8 | N+1 查询 — 权限控制 | `app/core/dependency.py` | 逐角色查询 API，4次查询 |
| 9 | API 刷新逻辑不完整 | `app/controllers/api.py` | 只刷新有 dependencies 的路由 |
| 10 | 多处冗余用户查询 | 多处 | 认证依赖已返回 AppUser，仍多次重复查询 |

### Medium（优化）

| # | 问题 | 文件 | 说明 |
|---|------|------|------|
| 11 | 目录结构不合理 | 整体 | 路由在 `api/v1/`，控制器在 `controllers/`，分离且命名混乱 |
| 12 | dept 软删除未使用 | `app/controllers/dept.py` | `is_deleted` 字段存在但未使用 |
| 13 | 无数据库连接池配置 | `app/settings/config.py` | 高并发下可能耗尽连接 |
| 14 | 支付/IM 为占位实现 | `wallet.py`, `im.py` | 微信/支付宝为 Mock URL，UserSig 为 Mock 字符串 |

### Low（代码质量）

| # | 问题 | 文件 | 说明 |
|---|------|------|------|
| 15 | CORS 生产环境可能为空 | `app/settings/config.py` | 非 DEBUG 模式 `CORS_ORIGINS` 可能为空数组 |
| 16 | gender 未使用 Pydantic enum | `app/schemas/app_user.py` | 应定义枚举验证 |
| 17 | `SuccessExtra` 冗余 data={} | `app/api/v1/app/anchor.py` | anchor_list 调用冗余 |
| 18 | `gift_send` 扣费非原子 | `app/api/v1/app/gift.py` | read-modify-write 存在竞态 |
| 19 | `refresh_api` 可简化 | `app/controllers/api.py` | 可用 `get_or_create` 替代 `get`+判断 |

---

## 修复方案

### #1 管理员 API 鉴权缺失

**修复**: 为 `users.py` 和 `apis.py` 中所有增删改接口添加 `DependPermission`。

```python
# users.py - 所有接口添加 dependencies
app_router.include_router(users_router, prefix="/user", dependencies=[DependPermission])

# apis.py - create/update/delete 已有 DependPermission，但路由注册时未传递
# 检查实际挂载方式，确保 dependencies 生效
```

### #2 审计日志支持 App 用户

**修复**: 中间件同时尝试解析 Admin Token 和 App Token：

```python
async def get_request_log(request: Request, response: Response) -> dict:
    token = request.headers.get("token")
    user_obj, username, user_type = None, "", "unknown"

    # 1. 尝试 App Token
    if token:
        try:
            app_user = await AppAuthControl.is_app_authed(token)
            user_obj = app_user
            username = app_user.nickname or app_user.phone
            user_type = "app"
        except Exception:
            pass

    # 2. 尝试 Admin Token
    if not user_obj and token:
        try:
            admin_user = await AuthControl.is_authed(token)
            user_obj = admin_user
            username = admin_user.username
            user_type = "admin"
        except Exception:
            pass

    data["user_id"] = user_obj.id if user_obj else 0
    data["username"] = username
    data["user_type"] = user_type
```

### #3 通话计费修复

**修复**: 移除 `dialing()` 中的预扣逻辑，心跳从第 1 个 tick 开始正常计费。

- `dialing()`: 只检查余额是否 >= call_price（不扣费），设置 Redis 心跳
- `heartbeat()`: 每5秒扣 `call_price // 12`，从心跳第1次开始
- Redis key `call:balance:{user_id}` 改为记录"预扣标记"，实际余额以 DB 为准

**变更**:
```python
# dialing() - 移除预扣
balance = await _get_balance(caller_id)
if balance < call_price:
    return Fail(code=501, msg="余额不足，请先充值")
# 不再: cache.set(balance - call_price)
# 改为: cache.set("pending", expire=3600)  # 预扣标记

# heartbeat() - 保持现有逻辑，fee_per_tick = call_price // 12
# 每次 heartbeat 从 DB 原子扣费
await _deduct_balance(caller_id, fee_per_tick)
```

### #4 提现冻结机制

**修复**: 新增 `frozen_balance` 字段，通过迁移添加：

```python
# 迁移文件
ALTER TABLE `app_user` ADD `frozen_balance` INT NOT NULL DEFAULT 0 COMMENT '冻结余额(分)';
```

**逻辑变更**:
```python
# withdraw_apply() - 冻结而非直接扣减
if app_user.balance < req_in.amount:
    return Fail(code=400, msg="余额不足")

# 冻结余额
app_user.balance -= req_in.amount
app_user.frozen_balance += req_in.amount
await app_user.save(update_fields=["balance", "frozen_balance"])
```

**审核通过**: `frozen_balance -= amount`，`balance` 不变
**审核拒绝**: `frozen_balance -= amount`，`balance += amount`（解冻）

### #5 Redis/DB 余额同步（原子化）

**修复**: `heartbeat` 中每次扣费使用原子 UPDATE，`call_end` 只清理 Redis。

```python
# heartbeat() - 原子扣费
updated = await AppUser.filter(id=caller_id, balance__gte=fee_per_tick).update(
    balance=AppUser.balance - fee_per_tick
)
if updated == 0:
    # 余额不足
    call_record.status = "ended"
    call_record.end_reason = "balance_empty"
    await call_record.save()
    return Fail(code=501, msg="余额不足，通话结束")
```

### #6 JWT Secret 从环境变量读取

```python
SECRET_KEY: str = os.getenv("SECRET_KEY", "dev-only-fallback-key-change-in-prod")
```

### #7 删除死代码 `_deduct_balance`

删除 `call.py:45-50` 的 `_deduct_balance` 函数（已迁移逻辑到 `heartbeat` 中）。

### #8 修复 N+1 查询

```python
# 原来: 逐角色查询
apis = [await role.apis for role in roles]

# 修改为: 预加载
roles = await current_user.roles.all().prefetch_related("apis")
apis = []
for role in roles:
    apis.extend(await role.apis.all())
# 或进一步优化: 一次性从所有角色收集 api_id，再 in 查询
```

### #9 API 刷新逻辑修复

移除 `len(route.dependencies) > 0` 过滤条件，扫描所有 `APIRoute`：

```python
for route in app.routes:
    if isinstance(route, APIRoute):
        # 扫描所有路由，包含无显式依赖的
```

### #10 消除冗余用户查询

重构 App API 层，统一通过 `DependAppAuth` 返回的 `AppUser` 对象获取用户信息，不再重复查询。

### #11 目录结构优化（渐进式）

短期：保持现有结构，在 `app/` 下按模块分组添加 `__init__.py` 导出
长期：迁移到 `app/modules/` 结构（本计划仅做标记）

### #12 dept 软删除

`dept.py` 控制器中删除操作改为软删除：
```python
await Dept.filter(id=dept_id).update(is_deleted=True)
```

### #13 数据库连接池配置

```python
TORTOISE_ORM = {
    "connections": {
        "mysql": {
            "credentials": {
                "minsize": 1,
                "maxsize": 10,
                # ...existing config
            }
        }
    }
}
```

### #14 占位实现标记

为 `wallet.py` 支付接口和 `im.py` UserSig 添加 `TODO` 注释和更明确的占位警告。

### #15 CORS 生产配置

```python
CORS_ORIGINS: typing.List = (
    [origin.strip() for origin in _cors_origins.split(",") if origin.strip()]
    if _cors_origins
    else (["http://localhost:3000", "http://localhost:8080"] if settings.DEBUG else ["*"])
)
```

### #16 Gender Pydantic Enum

```python
class GenderType(str, Enum):
    MALE = "male"
    FEMALE = "female"
    SECRET = "secret"

class AppRegisterIn(BaseModel):
    gender: GenderType = Field(default=GenderType.SECRET)
```

### #17 SuccessExtra 冗余 data={}

移除 `anchor_list` 中 `SuccessExtra` 的冗余 `data={}` 参数。

### #18 Gift 发送原子扣费

```python
updated = await AppUser.filter(id=sender_id, balance__gte=gift.price).update(
    balance=AppUser.balance - gift.price
)
if updated == 0:
    return Fail(code=501, msg="余额不足")
```

### #19 refresh_api 简化

```python
api_obj, _ = await Api.get_or_create(method=method, path=path, defaults={...})
if api_obj:
    await api_obj.update_from_dict({...}).save()
```

---

## 实施顺序

1. 迁移文件 — 新增 `frozen_balance` 字段
2. 模型 — `AppUser` 添加 `frozen_balance`
3. 安全修复 — #1 鉴权、#2 审计日志
4. 核心业务 — #3 通话、#4 提现、#5 同步
5. 配置 — #6 Secret、#15 CORS、#13 连接池
6. 代码质量 — #7~#10、#12、#14、#16~#19
7. 验证 — 运行 `flutter analyze`（前端），检查后端启动

---

## 风险评估

- **迁移风险**: 新增字段 `frozen_balance` 为非空默认值 0，向后兼容
- **计费风险**: 修改心跳逻辑需在测试环境充分验证扣费正确性
- **向后兼容**: 所有修改不影响已有 API 响应格式
