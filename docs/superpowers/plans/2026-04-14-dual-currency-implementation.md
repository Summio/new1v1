# 双币种系统实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现金币+钻石双币种系统，包括数据库改造、后端 API 改造、前端双余额展示、代币名称后台可配置。

**Architecture:** 金币（充值/消费）和钻石（主播收益/提现）完全分离，数据库增加 `coins`、`diamonds`、`frozen_diamonds` 字段；系统配置（代币名称）通过 `system_config` 表存储，供 Admin 和 App 共用。

**Tech Stack:** FastAPI + Tortoise ORM + MySQL (后端) | Flutter + Riverpod (前端)

---

## 文件变更总览

| 层 | 文件 | 操作 |
|---|---|---|
| 数据库 | `huanxi` DB | 新建 `system_config` 表，改 `app_user` 表，迁移数据 |
| 后端 Model | `app/models/admin.py` | 新增 `SystemConfig` 模型 |
| 后端 Model | `app/models/app_user.py` | `AppUser` 新增 `coins`、`diamonds`、`frozen_diamonds` 字段 |
| 后端 Schema | `app/schemas/app_api.py` | `WalletBalanceOut` 新增字段 |
| 后端 API | `app/api/v1/apis/` | 新建 `system_config.py` |
| 后端 API | `app/api/v1/app/user.py` | user info 返回 coins/diamonds |
| 后端 API | `app/api/v1/app/wallet.py` | wallet/balance 返回 coins/diamonds/token names |
| 后端 API | `app/api/v1/app/call.py` | 扣减 coins，增加主播 diamonds |
| 后端 API | `app/api/v1/app/gift.py` | 扣减 coins，增加主播 diamonds |
| 后端 API | `app/api/v1/app/wallet.py` | 充值改为增加 coins |
| 前端 Provider | `lib/app/providers/auth_provider.dart` | AuthState 新增 coins/diamonds/tokenName/diamondName |
| 前端 Provider | `lib/app/providers/auth_provider.dart` | `fetchUserInfo` / `login` 返回新字段 |
| 前端页面 | `lib/modules/home/profile_page.dart` | 余额卡片双货币展示 |
| 前端页面 | `lib/modules/profile/recharge_page.dart` | 代币名称动态读取 |
| 前端页面 | `lib/modules/home/home_page.dart` | 主播卡片支持 coins/diamonds 字段 |

---

## Task 1: 数据库改造 + 数据迁移

**文件:**
- 创建/修改: MySQL 数据库 `huanxi`

- [ ] **Step 1: 新建 `system_config` 表**

```sql
CREATE TABLE `system_config` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `cfg_key` varchar(64) NOT NULL UNIQUE,
  `cfg_value` varchar(255) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `created_at` datetime(6) DEFAULT CURRENT_TIMESTAMP(6),
  `updated_at` datetime(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO system_config (cfg_key, cfg_value, description) VALUES
  ('coin_name', '金币', '代币名称-用于充值和消费'),
  ('diamond_name', '钻石', '代币名称-用于主播收益');
```

Run: 在 MySQL 中执行上述 SQL

- [ ] **Step 2: 修改 `app_user` 表，添加新字段**

```sql
ALTER TABLE app_user
  ADD COLUMN coins BIGINT DEFAULT 0 COMMENT '金币余额(分)',
  ADD COLUMN diamonds BIGINT DEFAULT 0 COMMENT '钻石余额(分)',
  ADD COLUMN frozen_diamonds BIGINT DEFAULT 0 COMMENT '冻结钻石(分)';
```

- [ ] **Step 3: 数据迁移，将现有 balance 迁移到 coins**

```sql
UPDATE app_user SET coins = balance WHERE coins = 0 AND balance > 0;
```

Run: 验证 `SELECT id, balance, coins FROM app_user LIMIT 5;` 确认数据迁移正确

- [ ] **Step 4: 提交数据库迁移**

```bash
cd D:/1v1/new1v1/backend
aerich migrate --name add_coins_diamonds_system_config
aerich upgrade
```

---

## Task 2: 后端 Model — SystemConfig + AppUser 更新

**文件:**
- 创建: `backend/app/models/system_config.py`
- 修改: `backend/app/models/admin.py` (导出 SystemConfig)
- 修改: `backend/app/models/app_user.py` (AppUser 新增字段)

- [ ] **Step 1: 创建 `SystemConfig` 模型**

创建 `backend/app/models/system_config.py`:

```python
from tortoise import fields

from .base import BaseModel, TimestampMixin


class SystemConfig(BaseModel, TimestampMixin):
    """系统配置（键值对）"""
    cfg_key = fields.CharField(max_length=64, unique=True, description="配置键")
    cfg_value = fields.CharField(max_length=255, description="配置值")
    description = fields.CharField(max_length=255, null=True, description="说明")

    class Meta:
        table = "system_config"

    @classmethod
    async def get_value(cls, key: str, default: str = "") -> str:
        """获取配置值，不存在则返回默认值"""
        obj = await cls.filter(cfg_key=key).first()
        return obj.cfg_value if obj else default

    @classmethod
    async def get_all_as_dict(cls) -> dict:
        """获取所有配置为字典"""
        configs = await cls.all()
        return {c.cfg_key: c.cfg_value for c in configs}
```

- [ ] **Step 2: 导出 SystemConfig 模型**

修改 `backend/app/models/admin.py` 末尾，添加导出:

```python
from .system_config import SystemConfig

__all__ = ["Anchor", "Gift", "RechargeOrder", "WithdrawApply", "SystemConfig"]
```

- [ ] **Step 3: 更新 `AppUser` 模型，新增 coins/diamonds/frozen_diamonds 字段**

修改 `backend/app/models/app_user.py`，在 `frozen_balance` 字段后添加:

```python
    coins = fields.IntField(default=0, description="金币余额(分)")
    diamonds = fields.IntField(default=0, description="钻石余额(分)")
    frozen_diamonds = fields.IntField(default=0, description="冻结钻石(分)")
```

- [ ] **Step 4: 运行 aerich 生成迁移**

```bash
cd D:/1v1/new1v1/backend
aerich migrate --name add_system_config_model
aerich upgrade
```

- [ ] **Step 5: 提交**

```bash
git add app/models/system_config.py app/models/admin.py app/models/app_user.py
git commit -m "feat: add SystemConfig model and coins/diamonds fields to AppUser"
```

---

## Task 3: 后端 Admin API — 系统配置 CRUD

**文件:**
- 创建: `backend/app/api/v1/apis/system_config.py`
- 修改: `backend/app/api/v1/apis/apis.py` (注册路由)

- [ ] **Step 1: 创建系统配置 API**

创建 `backend/app/api/v1/apis/system_config.py`:

```python
from fastapi import APIRouter

from app.core.redis import cache
from app.models import SystemConfig
from app.schemas.base import Fail, Success

router = APIRouter()


@router.get("/system-config", summary="查询所有系统配置")
async def list_config():
    configs = await SystemConfig.all()
    data = {c.cfg_key: c.cfg_value for c in configs}
    return Success(data=data)


@router.put("/system-config/{cfg_key}", summary="更新指定配置")
async def update_config(cfg_key: str, value: str):
    obj = await SystemConfig.filter(cfg_key=cfg_key).first()
    if not obj:
        return Fail(code=404, msg=f"配置项 '{cfg_key}' 不存在")
    obj.cfg_value = value
    await obj.save()
    # 清除缓存
    await cache.delete(f"system_config:{cfg_key}")
    return Success(msg="更新成功")
```

- [ ] **Step 2: 注册路由**

修改 `backend/app/api/v1/apis/apis.py`，在文件末尾添加:

```python
from .system_config import router as system_config_router

router.include_router(system_config_router)
```

- [ ] **Step 3: 验证 API 可用**

启动后端后，访问 `GET /api/v1/apis/system-config` 应返回:
```json
{"code": 200, "data": {"coin_name": "金币", "diamond_name": "钻石"}}
```

- [ ] **Step 4: 提交**

```bash
git add app/api/v1/apis/system_config.py app/api/v1/apis/apis.py
git commit -m "feat: add system config CRUD API for admin"
```

---

## Task 4: 后端 App API — 用户信息 + 钱包余额返回 coins/diamonds

**文件:**
- 修改: `backend/app/api/v1/app/user.py` (user info 返回新字段)
- 修改: `backend/app/api/v1/app/wallet.py` (wallet/balance 返回新字段 + token names)
- 修改: `backend/app/schemas/app_api.py` (WalletBalanceOut 更新)

- [ ] **Step 1: 更新 `user/info` 返回 coins/diamonds**

修改 `backend/app/api/v1/app/user.py`:

```python
    return Success(
        data={
            "id": app_user.id,
            "phone": app_user.phone,
            "nickname": app_user.nickname or app_user.phone,
            "avatar": app_user.avatar or "",
            "gender": app_user.gender or "secret",
            "balance": app_user.balance,
            "coins": app_user.coins,
            "diamonds": app_user.diamonds,
            "frozen_balance": app_user.frozen_balance,
            "frozen_diamonds": app_user.frozen_diamonds,
            "status": app_user.status or "normal",
            "ban_reason": app_user.ban_reason or "",
            "is_anchor": app_user.is_anchor,
            "created_at": app_user.created_at.isoformat() if app_user.created_at else None,
        }
    )
```

- [ ] **Step 2: 更新 `WalletBalanceOut` Schema**

修改 `backend/app/schemas/app_api.py`，找到 `BalanceOut` 类，更新为:

```python
class BalanceOut(BaseModel):
    balance: int = 0
    coins: int = 0
    diamonds: int = 0
    frozen_balance: int = 0
    frozen_diamonds: int = 0
    coin_name: str = "金币"
    diamond_name: str = "钻石"
```

- [ ] **Step 3: 更新 `wallet/balance` API**

修改 `backend/app/api/v1/app/wallet.py`:

```python
from app.models import SystemConfig

@router.get("/wallet/balance", summary="查询余额", dependencies=[DependAppAuth])
async def wallet_balance():
    app_user: AppUser = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")
    coin_name = await SystemConfig.get_value("coin_name", "金币")
    diamond_name = await SystemConfig.get_value("diamond_name", "钻石")
    return Success(data=BalanceOut(
        balance=app_user.balance,
        coins=app_user.coins,
        diamonds=app_user.diamonds,
        frozen_balance=app_user.frozen_balance,
        frozen_diamonds=app_user.frozen_diamonds,
        coin_name=coin_name,
        diamond_name=diamond_name,
    ).model_dump())
```

- [ ] **Step 4: 验证 API**

启动后端，访问 `GET /api/v1/app/user/info` 应返回 `coins`、`diamonds` 字段；访问 `GET /api/v1/app/wallet/balance` 应返回所有新字段。

- [ ] **Step 5: 提交**

```bash
git add app/api/v1/app/user.py app/api/v1/app/wallet.py app/schemas/app_api.py
git commit -m "feat: add coins/diamonds/token_names to user info and wallet balance APIs"
```

---

## Task 5: 后端业务逻辑 — 充值/通话/送礼改为操作 coins + diamonds

**文件:**
- 修改: `backend/app/api/v1/app/wallet.py` (充值改为增加 coins)
- 修改: `backend/app/api/v1/app/call.py` (扣减 coins，增加主播 diamonds)
- 修改: `backend/app/api/v1/app/gift.py` (扣减 coins，增加主播 diamonds)

- [ ] **Step 1: 更新充值接口，改为增加 coins**

修改 `backend/app/api/v1/app/wallet.py` 的 `recharge_create` 函数末尾（支付回调后部分），在订单状态更新为 `completed` 时:

```python
# 支付完成后，增加用户金币余额
updated_user = await AppUser.filter(id=user_id).first()
if updated_user:
    await AppUser.filter(id=user_id).update(coins=AppUser.coins + req_in.amount)
```

> 注意：如果充值接口目前是占位实现（无真实支付回调），在创建订单时直接增加 coins 即可。确保注释说明生产环境应在支付回调中执行。

- [ ] **Step 2: 更新通话接口，扣减用户 coins，增加主播 diamonds**

修改 `backend/app/api/v1/app/call.py` 通话费用扣减逻辑:

找到原有 `balance` 扣减逻辑，改为:

```python
# 扣减用户金币，增加主播钻石（1:1）
updated = await AppUser.filter(id=caller_id, coins__gte=fee_per_tick).update(
    coins=AppUser.coins - fee_per_tick
)
if updated == 0:
    return Fail(code=501, msg="金币不足，请先充值")

# 增加主播钻石
anchor_user = await AppUser.filter(id=anchor_id).first()
if anchor_user:
    await AppUser.filter(id=anchor_id).update(diamonds=AppUser.diamonds + fee_per_tick)
```

> 注意：保留原有的 `balance` 相关逻辑用于旧数据兼容。新用户/新通话走 coins/diamonds。

- [ ] **Step 3: 更新送礼接口，扣减用户 coins，增加主播 diamonds**

修改 `backend/app/api/v1/app/gift.py` 礼物扣减逻辑:

找到原有 `balance` 扣减逻辑，改为:

```python
# 扣减用户金币，增加主播钻石（1:1）
updated = await AppUser.filter(id=sender_id, coins__gte=gift.price).update(
    coins=AppUser.coins - gift.price
)
if updated == 0:
    return Fail(code=501, msg="金币不足，请先充值")

# 增加主播钻石
anchor_user = await AppUser.filter(id=anchor_id).first()
if anchor_user:
    await AppUser.filter(id=anchor_id).update(diamonds=AppUser.diamonds + gift.price)
```

- [ ] **Step 4: 验证**

启动后端，通过测试账号验证：
- 充值后 `coins` 增加
- 通话/送礼后用户 `coins` 减少，主播 `diamonds` 增加

- [ ] **Step 5: 提交**

```bash
git add app/api/v1/app/wallet.py app/api/v1/app/call.py app/api/v1/app/gift.py
git commit -m "feat: update recharge/call/gift to use coins and diamonds fields"
```

---

## Task 6: 后端 — 钻石提现接口（新接口）

**文件:**
- 修改: `backend/app/api/v1/app/wallet.py` (新增 diamonds withdraw)

- [ ] **Step 1: 添加钻石提现接口**

在 `backend/app/api/v1/app/wallet.py` 末尾添加:

```python
@router.post("/withdraw/diamonds", summary="申请提取钻石", dependencies=[DependAppAuth])
async def withdraw_diamonds(req_in: WithdrawApplyIn):
    user_id = CTX_APP_USER_ID.get()
    app_user: AppUser = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")
    if not app_user.is_anchor:
        return Fail(code=403, msg="只有主播才能提取钻石")

    if app_user.diamonds < req_in.amount:
        return Fail(code=400, msg="钻石余额不足")

    updated = await AppUser.filter(id=user_id, diamonds__gte=req_in.amount).update(
        diamonds=AppUser.diamonds - req_in.amount,
        frozen_diamonds=AppUser.frozen_diamonds + req_in.amount,
    )
    if updated == 0:
        return Fail(code=400, msg="钻石余额不足，请稍后重试")

    await WithdrawApply.create(
        user_id=user_id,
        amount=req_in.amount,
        bank_name=req_in.bank_name,
        account_no=req_in.account_no,
        real_name=req_in.real_name,
        apply_type="diamonds",
        status="pending",
    )

    return Success(msg="提现申请已提交，审核通过后到账")
```

- [ ] **Step 2: 更新 `WithdrawApply` 模型支持 apply_type**

检查 `backend/app/models/admin.py` 中 `WithdrawApply` 模型是否有 `apply_type` 字段。如果没有，添加:

```python
apply_type = fields.CharField(max_length=20, null=True, default="balance", description="提现类型: balance/diamonds")
```

如果没有该字段，需要通过 SQL 添加:
```sql
ALTER TABLE withdraw_apply ADD COLUMN apply_type VARCHAR(20) DEFAULT 'balance' COMMENT '提现类型';
```

- [ ] **Step 3: 提交**

```bash
git add app/api/v1/app/wallet.py app/models/admin.py
git commit -m "feat: add diamond withdraw API endpoint"
```

---

## Task 7: 前端 — AuthState 更新 + 读取代币名称

**文件:**
- 修改: `lib/app/providers/auth_provider.dart`

- [ ] **Step 1: 更新 `AuthState` 新增字段**

修改 `lib/app/providers/auth_provider.dart`，在 `AuthState` 类中新增:

```dart
  final int coins;
  final int diamonds;
  final String coinName;
  final String diamondName;
```

构造函数和 `copyWith` 也需同步更新:

```dart
AuthState({
    ...
    this.coins = 0,
    this.diamonds = 0,
    this.coinName = '金币',
    this.diamondName = '钻石',
  });
```

copyWith:
```dart
coins: coins ?? this.coins,
diamonds: diamonds ?? this.diamonds,
coinName: coinName ?? this.coinName,
diamondName: diamondName ?? this.diamondName,
```

- [ ] **Step 2: 更新 `fetchUserInfo` 解析新字段**

在 `fetchUserInfo` 中，解析响应时添加:

```dart
final coins = respData['coins'] as int? ?? 0;
final diamonds = respData['diamonds'] as int? ?? 0;

state = state.copyWith(
    ...
    coins: coins,
    diamonds: diamonds,
    coinName: '金币',    // user/info 不返回 token name，后续从 wallet/balance 获取
    diamondName: '钻石',
);
```

> 注：user/info 接口目前不返回 coin_name/diamond_name，在 wallet/balance 接口获取。

- [ ] **Step 3: 更新 `login` 方法解析新字段**

在 `login` 方法中，从响应解析 coins/diamonds:

```dart
final coins = respData['coins'] as int? ?? 0;
final diamonds = respData['diamonds'] as int? ?? 0;

state = state.copyWith(
    ...
    coins: coins,
    diamonds: diamonds,
);
```

- [ ] **Step 4: 新增 `fetchWalletBalance` 方法刷新 coins/diamonds**

在 `AuthNotifier` 中添加:

```dart
/// 刷新钱包余额（从 wallet/balance 获取最新 coins/diamonds 和 token names）
Future<void> fetchWalletBalance() async {
    try {
        final data = await _dio.apiGet(ApiEndpoints.walletBalance);
        final respData = data['data'] as Map<String, dynamic>?;
        if (respData == null) return;

        state = state.copyWith(
            coins: respData['coins'] as int? ?? 0,
            diamonds: respData['diamonds'] as int? ?? 0,
            coinName: respData['coin_name'] as String? ?? '金币',
            diamondName: respData['diamond_name'] as String? ?? '钻石',
        );
    } catch (_) {}
}
```

- [ ] **Step 5: 提交**

```bash
git add lib/app/providers/auth_provider.dart
git commit -m "feat: add coins/diamonds/tokenName fields to AuthState"
```

---

## Task 8: 前端 — "我的"页面余额卡片双货币展示

**文件:**
- 修改: `lib/modules/home/profile_page.dart`

- [ ] **Step 1: 更新余额卡片布局**

修改 `profile_page.dart` 中余额卡片部分（SliverToBoxAdapter），使用双列布局:

```dart
SliverToBoxAdapter(
    child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            gradient: AppTheme.balanceGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppTheme.elevatedShadow,
        ),
        child: Column(
            children: [
                // 第一行：金币余额
                Row(
                    children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    Text(
                                        '${authState.coinName}余额',
                                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                        (authState.coins ~/ 100).toString(),
                                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                                    ),
                                ],
                            ),
                        ),
                        GestureDetector(
                            onTap: () => context.push(AppRoutes.recharge),
                            child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                    '充值',
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                            ),
                        ),
                    ],
                ),
                const SizedBox(height: 16),
                // 分隔线
                Container(height: 1, color: Colors.white.withValues(alpha: 0.2)),
                const SizedBox(height: 16),
                // 第二行：钻石余额
                Row(
                    children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    Text(
                                        '${authState.diamondName}余额',
                                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                        (authState.diamonds ~/ 100).toString(),
                                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                                    ),
                                ],
                            ),
                        ),
                        if (isAnchor)
                            GestureDetector(
                                onTap: () {},
                                child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                        '提现',
                                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                ),
                            ),
                    ],
                ),
            ],
        ),
    ),
),
```

- [ ] **Step 2: 在页面初始化时刷新余额**

在 `ProfilePage` 的 `build` 方法中，添加 `useEffect` 等效逻辑（通过 `ConsumerStatefulWidget` 或在现有结构中调用 `fetchWalletBalance`）:

在 `profile_page.dart` 中，如果 `ProfilePage` 是 `ConsumerWidget`，需要改为 `ConsumerStatefulWidget`，在 `initState` 中调用 `fetchWalletBalance`。

如果已经是 `ConsumerWidget`，在 `build` 方法开头添加（使用 `Future.microtask`）:

```dart
// 在 ConsumerStatefulWidget 的 initState 中:
Future.microtask(() {
    ref.read(authProvider.notifier).fetchWalletBalance();
});
```

> 如果 ProfilePage 已是 ConsumerStatefulWidget，直接在 initState 中调用。如果需要转换，参考 home_page.dart 的写法。

- [ ] **Step 3: 提交**

```bash
git add lib/modules/home/profile_page.dart
git commit -m "feat: display dual currency balance on profile page"
```

---

## Task 9: 前端 — 充值页代币名称动态读取

**文件:**
- 修改: `lib/modules/profile/recharge_page.dart`

- [ ] **Step 1: 从 authState 读取 coinName 动态显示**

修改 `recharge_page.dart`，将硬编码的"金币"替换为从 authState 读取:

```dart
// 在 build 方法中获取
final coinName = ref.watch(authProvider).coinName;
final authState = ref.watch(authProvider);
```

更新说明文案（第66-67行）:
```dart
child: Text(
    '1元 = 10 $coinName，$coinName用于拨打主播电话',
    style: const TextStyle(fontSize: 13, color: AppTheme.secondaryDark),
),
```

更新每个套餐的显示（第127行 "金币"）:
```dart
Text(
    '${pkg['coins']}$coinName',
    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
),
```

- [ ] **Step 2: 提交**

```bash
git add lib/modules/profile/recharge_page.dart
git commit -m "feat: read coin name dynamically on recharge page"
```

---

## Task 10: 前端 — 主播卡片支持 diamonds 字段

**文件:**
- 修改: `lib/app/providers/anchor_provider.dart` (AnchorInfo 新增 diamonds 字段)
- 修改: `lib/modules/home/home_page.dart` (主播卡片显示钻石余额)

- [ ] **Step 1: 更新 `AnchorInfo` 新增 diamonds 字段**

修改 `lib/app/providers/anchor_provider.dart` 的 `AnchorInfo` 类:

```dart
class AnchorInfo {
    ...
    final int? diamonds;

    const AnchorInfo({
        ...
        this.diamonds,
    });

    factory AnchorInfo.fromJson(Map<String, dynamic> json) {
        return AnchorInfo(
            ...
            diamonds: json['diamonds'] as int?,
        );
    }
}
```

- [ ] **Step 2: 更新主播卡片显示钻石余额**

修改 `lib/modules/home/home_page.dart` 中 `_AnchorCard` 组件，在底部文字区域显示主播钻石余额:

```dart
// 在底部文字区域添加钻石显示
Text(
    '${(anchor.diamonds ?? 0) ~/ 100} 钻石',
    style: TextStyle(
        fontSize: 10,
        color: Colors.white.withValues(alpha: 0.8),
        fontWeight: FontWeight.w500,
    ),
),
```

- [ ] **Step 3: 提交**

```bash
git add lib/app/providers/anchor_provider.dart lib/modules/home/home_page.dart
git commit -m "feat: add diamonds field to AnchorInfo and display in card"
```

---

## 自检清单

完成所有任务后，运行以下验证：

1. **数据库**: `SELECT id, balance, coins, diamonds FROM app_user LIMIT 5;` — coins 应等于 balance
2. **Admin API**: `GET /api/v1/apis/system-config` — 返回 coin_name/diamond_name
3. **User Info API**: `GET /api/v1/app/user/info` — 返回 coins/diamonds
4. **Wallet Balance API**: `GET /api/v1/app/wallet/balance` — 返回 coins/diamonds/token names
5. **Flutter analyze**: `flutter analyze` 无 error
6. **充值测试**: 充值后 coins 增加
7. **通话测试**: 用户 coins 减少，主播 diamonds 增加
