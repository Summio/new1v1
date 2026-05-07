# IM Text Message Billing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add configurable per-text-message IM billing where non-anchor users pay coins to message anchors and anchors receive diamond income.

**Architecture:** Keep Tencent IM text delivery in the Flutter client. Add a backend pre-send charge endpoint that validates config, applies atomic coin/diamond updates, records an idempotent charge row, and returns current balances. Admin config is stored in `system_config` through dedicated system APIs and surfaced in a focused Vue settings page.

**Tech Stack:** FastAPI, Tortoise ORM, Aerich migrations, Pydantic, pytest, Flutter/Riverpod/Dio, Vue3 + Naive UI.

---

## File Map

- Modify `backend/app/schemas/system.py`: add admin IM text billing config schemas.
- Modify `backend/app/schemas/app_api.py`: add App IM text charge request/response schemas and transaction type comment.
- Modify `backend/app/models/admin.py`: add `ImTextMessageChargeRecord`.
- Modify `backend/app/api/v1/apis/system/__init__.py`: register admin config router.
- Create `backend/app/api/v1/apis/system/im_text_billing_config.py`: dedicated admin GET/PUT config endpoints.
- Modify `backend/app/api/v1/app/bootstrap.py`: include `im_text_billing`.
- Modify `backend/app/api/v1/app/im.py`: add App text-charge endpoint.
- Create `backend/app/services/im_text_billing_service.py`: parsing config and charging logic.
- Modify `backend/app/api/v1/app/wallet.py`: include IM text records in wallet transactions.
- Modify `backend/app/api/v1/app_users/app_users.py`: include IM text records in admin user bill list.
- Create `backend/migrations/models/23_20260507100000_im_text_message_billing.py`: create charge table and seed config keys.
- Create `backend/tests/test_im_text_billing.py`: behavior and schema tests for config/service/route contracts.
- Modify `backend/tests/test_atomic_balance_field_usage.py`: include new billing service in atomic update guard.
- Modify `huanxi/lib/core/constants/api_endpoints.dart`: add `imTextCharge`.
- Modify `huanxi/lib/core/network/response_parsers.dart`: add parser/model for IM text charge response.
- Modify `huanxi/lib/app/providers/auth_provider.dart`: parse bootstrap `im_text_billing`.
- Modify `huanxi/lib/modules/im/im_page.dart`: call charge endpoint before `sendTextMessage`.
- Modify `backend/web/src/api/system.js`: add admin config API methods.
- Modify `backend/web/src/api/index.js`: expose new system methods through existing spread.
- Create `backend/web/src/views/system/im-text-billing/index.vue`: config UI.
- Modify `backend/app/core/init_app.py`: seed a system menu entry for `/system/im-text-billing` on fresh installs.

## Assumptions

- Only non-anchor users messaging anchor users are charged.
- Each successful charge is idempotent by `(sender_id, request_id)`.
- Backend uses integer coin/diamond amounts consistently with existing gift and call code.
- If Tencent IM SDK send fails after a successful charge, no automatic refund is implemented in this task.

---

### Task 1: Backend Schemas And Config Parsing

**Files:**
- Modify: `backend/app/schemas/system.py`
- Modify: `backend/app/schemas/app_api.py`
- Create: `backend/app/services/im_text_billing_service.py`
- Test: `backend/tests/test_im_text_billing.py`

- [ ] **Step 1: Write failing schema/config tests**

Add to `backend/tests/test_im_text_billing.py`:

```python
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.schemas.app_api import IMTextChargeIn
from app.schemas.system import IMTextBillingConfigIn
from app.services.im_text_billing_service import (
    DEFAULT_IM_TEXT_ANCHOR_SHARE_BPS,
    DEFAULT_IM_TEXT_PRICE,
    parse_im_text_billing_config,
)


BACKEND_ROOT = Path(__file__).resolve().parents[1]


def _read_backend_file(relative_path: str) -> str:
    return (BACKEND_ROOT / relative_path).read_text(encoding="utf-8")


def test_im_text_billing_config_defaults_are_safe() -> None:
    config = parse_im_text_billing_config({})

    assert config.enabled is False
    assert config.price == DEFAULT_IM_TEXT_PRICE
    assert config.anchor_share_bps == DEFAULT_IM_TEXT_ANCHOR_SHARE_BPS


def test_im_text_billing_config_rejects_enabled_zero_price() -> None:
    with pytest.raises(ValidationError):
        IMTextBillingConfigIn(enabled=True, price=0, anchor_share_bps=5000)


def test_im_text_billing_config_rejects_invalid_share() -> None:
    with pytest.raises(ValidationError):
        IMTextBillingConfigIn(enabled=False, price=0, anchor_share_bps=10001)


def test_im_text_charge_request_requires_request_id() -> None:
    item = IMTextChargeIn(receiver_user_id=2, request_id="req_123456")
    assert item.receiver_user_id == 2

    with pytest.raises(ValidationError):
        IMTextChargeIn(receiver_user_id=2, request_id="short")


def test_im_text_config_route_contract_exists() -> None:
    content = _read_backend_file("app/api/v1/apis/system/__init__.py")
    assert "im_text_billing_config_router" in content
    assert 'prefix="/im-text-billing-config"' in content
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd backend
pytest -q tests/test_im_text_billing.py
```

Expected: fail because `IMTextBillingConfigIn`, `IMTextChargeIn`, and the service module do not exist.

- [ ] **Step 3: Implement minimal schemas and parser**

Add to `backend/app/schemas/system.py`:

```python
from pydantic import BaseModel, Field, model_validator


class IMTextBillingConfigIn(BaseModel):
    """IM 文字消息计费配置输入"""
    enabled: bool = Field(default=False, description="是否开启文字聊天扣费")
    price: int = Field(default=0, ge=0, le=1000000, description="每条文字消息扣费金币数")
    anchor_share_bps: int = Field(default=5000, ge=0, le=10000, description="主播分成万分比")

    @model_validator(mode="after")
    def validate_enabled_price(self):
        if self.enabled and self.price <= 0:
            raise ValueError("price must be greater than 0 when enabled")
        return self


class IMTextBillingConfigOut(IMTextBillingConfigIn):
    """IM 文字消息计费配置输出"""
```

Add to `backend/app/schemas/app_api.py` under `# ===== IM =====`:

```python
class IMTextChargeIn(BaseModel):
    receiver_user_id: int = Field(..., gt=0, description="接收方 App 用户 ID")
    request_id: str = Field(..., min_length=8, max_length=64, description="客户端请求幂等 ID")


class IMTextChargeOut(BaseModel):
    charged: bool = False
    price: int = 0
    anchor_income_diamonds: int = 0
    coins: int = 0
    diamonds: int = 0
    receiver_user_id: int
    request_id: str
```

Create `backend/app/services/im_text_billing_service.py`:

```python
from dataclasses import dataclass

from app.schemas.system import IMTextBillingConfigOut
from app.utils.parse import clamp_int, safe_parse_int

DEFAULT_IM_TEXT_PRICE = 0
DEFAULT_IM_TEXT_ANCHOR_SHARE_BPS = 5000
MAX_ANCHOR_SHARE_BPS = 10000


@dataclass(frozen=True)
class IMTextBillingConfig:
    enabled: bool
    price: int
    anchor_share_bps: int


def parse_bool_config(raw: str | None, default: bool = False) -> bool:
    value = (raw or "").strip().lower()
    if value in {"1", "true", "yes", "on"}:
        return True
    if value in {"0", "false", "no", "off"}:
        return False
    return default


def parse_im_text_billing_config(config_map: dict[str, str]) -> IMTextBillingConfig:
    enabled = parse_bool_config(config_map.get("im_text_message_billing_enabled"), False)
    price = clamp_int(
        safe_parse_int(config_map.get("im_text_message_price"), DEFAULT_IM_TEXT_PRICE),
        0,
        1000000,
    )
    share = clamp_int(
        safe_parse_int(
            config_map.get("im_text_message_anchor_share_bps"),
            DEFAULT_IM_TEXT_ANCHOR_SHARE_BPS,
        ),
        0,
        MAX_ANCHOR_SHARE_BPS,
    )
    return IMTextBillingConfig(enabled=enabled, price=price, anchor_share_bps=share)


def dump_im_text_billing_config(config: IMTextBillingConfig) -> dict[str, int | bool]:
    return IMTextBillingConfigOut(
        enabled=config.enabled,
        price=config.price,
        anchor_share_bps=config.anchor_share_bps,
    ).model_dump()
```

- [ ] **Step 4: Run test to verify partial pass**

Run:

```bash
cd backend
pytest -q tests/test_im_text_billing.py
```

Expected: only route contract test fails.

---

### Task 2: Admin Config API

**Files:**
- Create: `backend/app/api/v1/apis/system/im_text_billing_config.py`
- Modify: `backend/app/api/v1/apis/system/__init__.py`
- Test: `backend/tests/test_im_text_billing.py`

- [ ] **Step 1: Extend failing route tests**

Append:

```python
def test_im_text_config_api_uses_system_config_and_clears_cache() -> None:
    content = _read_backend_file("app/api/v1/apis/system/im_text_billing_config.py")

    assert "@router.get(" in content
    assert "@router.put(" in content
    assert "SystemConfig.get_all_as_dict" in content
    assert "SYSTEM_CONFIG_CACHE_KEY" in content
    assert "im_text_message_billing_enabled" in content
    assert "im_text_message_price" in content
    assert "im_text_message_anchor_share_bps" in content
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd backend
pytest -q tests/test_im_text_billing.py::test_im_text_config_api_uses_system_config_and_clears_cache
```

Expected: fail because file does not exist.

- [ ] **Step 3: Implement admin config router**

Create `backend/app/api/v1/apis/system/im_text_billing_config.py`:

```python
from fastapi import APIRouter, HTTPException

from app.core.redis import get_redis
from app.models.system_config import SYSTEM_CONFIG_CACHE_KEY, SystemConfig
from app.schemas.base import Success
from app.schemas.system import IMTextBillingConfigIn
from app.services.im_text_billing_service import (
    dump_im_text_billing_config,
    parse_im_text_billing_config,
)

router = APIRouter()

CONFIG_ITEMS = {
    "im_text_message_billing_enabled": "文字聊天扣费开关",
    "im_text_message_price": "文字聊天每条扣费金币数",
    "im_text_message_anchor_share_bps": "文字聊天主播分成比例",
}


@router.get("", summary="获取文字聊天计费配置")
async def get_im_text_billing_config():
    config_map = await SystemConfig.get_all_as_dict()
    config = parse_im_text_billing_config(config_map)
    return Success(data=dump_im_text_billing_config(config))


@router.put("", summary="更新文字聊天计费配置")
async def update_im_text_billing_config(config_in: IMTextBillingConfigIn):
    values = {
        "im_text_message_billing_enabled": "true" if config_in.enabled else "false",
        "im_text_message_price": str(config_in.price),
        "im_text_message_anchor_share_bps": str(config_in.anchor_share_bps),
    }
    try:
        for key, value in values.items():
            obj = await SystemConfig.filter(cfg_key=key).first()
            if obj:
                obj.cfg_value = value
                obj.description = CONFIG_ITEMS[key]
                await obj.save(update_fields=["cfg_value", "description"])
            else:
                await SystemConfig.create(
                    cfg_key=key,
                    cfg_value=value,
                    description=CONFIG_ITEMS[key],
                )
        redis = await get_redis()
        await redis.delete(SYSTEM_CONFIG_CACHE_KEY)
    except Exception as exc:
        raise HTTPException(status_code=500, detail="配置更新失败") from exc
    return Success(msg="配置已更新")
```

Modify `backend/app/api/v1/apis/system/__init__.py`:

```python
from .im_text_billing_config import router as im_text_billing_config_router

system_router.include_router(
    im_text_billing_config_router,
    prefix="/im-text-billing-config",
    tags=["系统配置-文字聊天计费"],
)
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd backend
pytest -q tests/test_im_text_billing.py
```

Expected: pass.

---

### Task 3: Model, Migration, And Charge Service

**Files:**
- Modify: `backend/app/models/admin.py`
- Create: `backend/migrations/models/23_20260507100000_im_text_message_billing.py`
- Modify: `backend/app/services/im_text_billing_service.py`
- Test: `backend/tests/test_im_text_billing.py`
- Modify: `backend/tests/test_atomic_balance_field_usage.py`

- [ ] **Step 1: Write failing model/migration/service contract tests**

Append:

```python
def test_im_text_charge_model_and_migration_exist() -> None:
    model_content = _read_backend_file("app/models/admin.py")
    migration_content = _read_backend_file(
        "migrations/models/23_20260507100000_im_text_message_billing.py"
    )

    assert "class ImTextMessageChargeRecord" in model_content
    assert 'table = "im_text_message_charge_record"' in model_content
    assert "unique_together = ((\"sender_id\", \"request_id\"),)" in model_content
    assert "CREATE TABLE IF NOT EXISTS `im_text_message_charge_record`" in migration_content
    assert "im_text_message_billing_enabled" in migration_content


def test_im_text_charge_service_uses_atomic_balance_updates() -> None:
    content = _read_backend_file("app/services/im_text_billing_service.py")

    assert "async def charge_im_text_message" in content
    assert 'coins=F("coins") - price' in content
    assert 'diamonds=F("diamonds") + anchor_income_diamonds' in content
    assert "in_transaction()" in content
    assert "coins__gte=price" in content
```

Modify `backend/tests/test_atomic_balance_field_usage.py`:

```python
TARGET_FILES = [
    Path("app/api/v1/app/gift.py"),
    Path("app/api/v1/app/wallet.py"),
    Path("app/api/v1/withdraw/withdraw.py"),
    Path("app/services/im_text_billing_service.py"),
]
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd backend
pytest -q tests/test_im_text_billing.py::test_im_text_charge_model_and_migration_exist tests/test_im_text_billing.py::test_im_text_charge_service_uses_atomic_balance_updates
```

Expected: fail because model/migration/service charge function are missing.

- [ ] **Step 3: Add model and migration**

Add to `backend/app/models/admin.py` after `GiftRecord`:

```python
class ImTextMessageChargeRecord(BaseModel, TimestampMixin):
    """IM 文字消息扣费记录"""
    sender_id = fields.BigIntField(description="发送方用户ID", index=True)
    receiver_id = fields.BigIntField(description="接收方用户ID", index=True)
    request_id = fields.CharField(max_length=64, description="客户端请求幂等ID")
    price = fields.BigIntField(default=0, description="文字消息扣费金币数")
    anchor_share_bps = fields.IntField(default=5000, description="主播分成比例快照(万分比)")
    anchor_income_diamonds = fields.BigIntField(default=0, description="主播收益钻石")
    status = fields.CharField(max_length=20, default="charged", description="charged", index=True)

    class Meta:
        table = "im_text_message_charge_record"
        unique_together = (("sender_id", "request_id"),)
```

Create migration `backend/migrations/models/23_20260507100000_im_text_message_billing.py` using the local Aerich style:

```python
from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE TABLE IF NOT EXISTS `im_text_message_charge_record` (
            `id` INT NOT NULL PRIMARY KEY AUTO_INCREMENT,
            `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
            `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
            `sender_id` BIGINT NOT NULL,
            `receiver_id` BIGINT NOT NULL,
            `request_id` VARCHAR(64) NOT NULL,
            `price` BIGINT NOT NULL DEFAULT 0,
            `anchor_share_bps` INT NOT NULL DEFAULT 5000,
            `anchor_income_diamonds` BIGINT NOT NULL DEFAULT 0,
            `status` VARCHAR(20) NOT NULL DEFAULT 'charged',
            KEY `idx_im_text_sender` (`sender_id`),
            KEY `idx_im_text_receiver` (`receiver_id`),
            KEY `idx_im_text_status` (`status`),
            UNIQUE KEY `uid_im_text_sender_request` (`sender_id`, `request_id`)
        ) CHARACTER SET utf8mb4;

        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'im_text_message_billing_enabled', 'false', '文字聊天扣费开关', NOW(6), NOW(6)
        WHERE NOT EXISTS (SELECT 1 FROM `system_config` WHERE `cfg_key` = 'im_text_message_billing_enabled');

        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'im_text_message_price', '0', '文字聊天每条扣费金币数', NOW(6), NOW(6)
        WHERE NOT EXISTS (SELECT 1 FROM `system_config` WHERE `cfg_key` = 'im_text_message_price');

        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'im_text_message_anchor_share_bps', '5000', '文字聊天主播分成比例', NOW(6), NOW(6)
        WHERE NOT EXISTS (SELECT 1 FROM `system_config` WHERE `cfg_key` = 'im_text_message_anchor_share_bps');
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DROP TABLE IF EXISTS `im_text_message_charge_record`;
    """
```

- [ ] **Step 4: Implement charge service**

Extend `backend/app/services/im_text_billing_service.py`:

```python
from tortoise.expressions import F
from tortoise.transactions import in_transaction

from app.models import AppUser, ImTextMessageChargeRecord, SystemConfig


@dataclass(frozen=True)
class IMTextChargeResult:
    charged: bool
    price: int
    anchor_income_diamonds: int
    coins: int
    diamonds: int
    receiver_user_id: int
    request_id: str


class IMTextBillingError(Exception):
    def __init__(self, code: int, message: str):
        self.code = code
        self.message = message
        super().__init__(message)


async def load_im_text_billing_config() -> IMTextBillingConfig:
    return parse_im_text_billing_config(await SystemConfig.get_all_as_dict())


async def charge_im_text_message(
    *,
    sender_id: int,
    receiver_user_id: int,
    request_id: str,
) -> IMTextChargeResult:
    if int(sender_id) == int(receiver_user_id):
        raise IMTextBillingError(400, "不能和自己聊天")

    sender = await AppUser.filter(id=sender_id, status="normal").first()
    receiver = await AppUser.filter(id=receiver_user_id, status="normal").first()
    if not sender:
        raise IMTextBillingError(401, "登录状态异常")
    if not receiver:
        raise IMTextBillingError(404, "目标用户不存在或状态异常")

    existing = await ImTextMessageChargeRecord.filter(
        sender_id=sender_id,
        request_id=request_id,
    ).first()
    if existing:
        current = await AppUser.filter(id=sender_id).first()
        return IMTextChargeResult(
            charged=True,
            price=int(existing.price),
            anchor_income_diamonds=int(existing.anchor_income_diamonds),
            coins=int(current.coins if current else sender.coins),
            diamonds=int(current.diamonds if current else sender.diamonds),
            receiver_user_id=receiver_user_id,
            request_id=request_id,
        )

    config = await load_im_text_billing_config()
    should_charge = config.enabled and config.price > 0 and bool(receiver.is_anchor) and not bool(sender.is_anchor)
    if not should_charge:
        return IMTextChargeResult(
            charged=False,
            price=0,
            anchor_income_diamonds=0,
            coins=int(sender.coins),
            diamonds=int(sender.diamonds),
            receiver_user_id=receiver_user_id,
            request_id=request_id,
        )

    price = int(config.price)
    anchor_income_diamonds = price * int(config.anchor_share_bps) // MAX_ANCHOR_SHARE_BPS
    async with in_transaction() as conn:
        updated = await AppUser.filter(
            id=sender_id,
            coins__gte=price,
        ).using_db(conn).update(coins=F("coins") - price)
        if updated == 0:
            raise IMTextBillingError(501, "余额不足，请先充值")
        if anchor_income_diamonds > 0:
            await AppUser.filter(id=receiver_user_id).using_db(conn).update(
                diamonds=F("diamonds") + anchor_income_diamonds
            )
        await ImTextMessageChargeRecord.create(
            sender_id=sender_id,
            receiver_id=receiver_user_id,
            request_id=request_id,
            price=price,
            anchor_share_bps=int(config.anchor_share_bps),
            anchor_income_diamonds=anchor_income_diamonds,
            status="charged",
            using_db=conn,
        )
        current = await AppUser.filter(id=sender_id).using_db(conn).first()

    return IMTextChargeResult(
        charged=True,
        price=price,
        anchor_income_diamonds=anchor_income_diamonds,
        coins=int(current.coins if current else 0),
        diamonds=int(current.diamonds if current else 0),
        receiver_user_id=receiver_user_id,
        request_id=request_id,
    )
```

- [ ] **Step 5: Run tests**

Run:

```bash
cd backend
pytest -q tests/test_im_text_billing.py tests/test_atomic_balance_field_usage.py
```

Expected: pass.

---

### Task 4: App Charge Endpoint And Bootstrap

**Files:**
- Modify: `backend/app/api/v1/app/im.py`
- Modify: `backend/app/api/v1/app/bootstrap.py`
- Test: `backend/tests/test_im_text_billing.py`

- [ ] **Step 1: Write failing route/bootstrap tests**

Append:

```python
def test_im_text_charge_endpoint_contract_exists() -> None:
    content = _read_backend_file("app/api/v1/app/im.py")

    assert '@router.post("/im/text-charge"' in content
    assert "IMTextChargeIn" in content
    assert "charge_im_text_message" in content
    assert "IMTextBillingError" in content
    assert "Fail(code=exc.code" in content


def test_bootstrap_returns_im_text_billing_config() -> None:
    content = _read_backend_file("app/api/v1/app/bootstrap.py")

    assert "parse_im_text_billing_config" in content
    assert '"im_text_billing"' in content or "'im_text_billing'" in content
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd backend
pytest -q tests/test_im_text_billing.py::test_im_text_charge_endpoint_contract_exists tests/test_im_text_billing.py::test_bootstrap_returns_im_text_billing_config
```

Expected: fail because endpoint/bootstrap field are missing.

- [ ] **Step 3: Implement endpoint**

Modify imports in `backend/app/api/v1/app/im.py`:

```python
from app.schemas.app_api import IMSigOut, IMTextChargeIn, IMTextChargeOut
from app.services.im_text_billing_service import (
    IMTextBillingError,
    charge_im_text_message,
)
```

Add route:

```python
@router.post("/im/text-charge", summary="文字消息发送前扣费", dependencies=[Depends(DependAppAuth)])
async def charge_text_message(req_in: IMTextChargeIn):
    sender_id = CTX_APP_USER_ID.get()
    try:
        result = await charge_im_text_message(
            sender_id=int(sender_id),
            receiver_user_id=int(req_in.receiver_user_id),
            request_id=req_in.request_id.strip(),
        )
    except IMTextBillingError as exc:
        return Fail(code=exc.code, msg=exc.message)
    return Success(data=IMTextChargeOut(**result.__dict__).model_dump())
```

- [ ] **Step 4: Add bootstrap field**

Modify `backend/app/api/v1/app/bootstrap.py`:

```python
from app.services.im_text_billing_service import (
    dump_im_text_billing_config,
    parse_im_text_billing_config,
)
```

Inside response data:

```python
"im_text_billing": dump_im_text_billing_config(
    parse_im_text_billing_config(config_map)
),
```

- [ ] **Step 5: Run tests**

Run:

```bash
cd backend
pytest -q tests/test_im_text_billing.py
```

Expected: pass.

---

### Task 5: Wallet And Admin Bill Records

**Files:**
- Modify: `backend/app/api/v1/app/wallet.py`
- Modify: `backend/app/api/v1/app_users/app_users.py`
- Test: `backend/tests/test_im_text_billing.py`

- [ ] **Step 1: Write failing bill tests**

Append:

```python
def test_wallet_transactions_include_im_text_records() -> None:
    content = _read_backend_file("app/api/v1/app/wallet.py")

    assert "im_text_message_charge_record" in content
    assert "文字聊天收益" in content
    assert "文字聊天" in content


def test_admin_user_bill_include_im_text_filter() -> None:
    content = _read_backend_file("app/api/v1/app_users/app_users.py")

    assert "im_text" in content
    assert "im_text_message_charge_record" in content
    assert '"biz_type": "im_text"' in content
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd backend
pytest -q tests/test_im_text_billing.py::test_wallet_transactions_include_im_text_records tests/test_im_text_billing.py::test_admin_user_bill_include_im_text_filter
```

Expected: fail because SQL is not wired yet.

- [ ] **Step 3: Implement wallet SQL additions**

In `wallet_transactions`, add two union branches using the file’s existing raw SQL pattern:

```python
# im text sent (coins expense)
if type in ("all", "im_text", "coins"):
    queries.append(
        f"SELECT id, 'im_text' AS rec_type, price AS amount, created_at, 0 AS is_income "
        f"FROM im_text_message_charge_record WHERE sender_id = {placeholder} AND status = 'charged'"
    )

# im text receive (diamonds income)
if type in ("all", "im_text", "diamonds"):
    queries.append(
        f"SELECT id, 'im_text' AS rec_type, anchor_income_diamonds AS amount, created_at, 1 AS is_income "
        f"FROM im_text_message_charge_record WHERE receiver_id = {placeholder} "
        f"AND status = 'charged' AND anchor_income_diamonds > 0"
    )
```

Update title map:

```python
"im_text": "文字聊天收益" if is_income else "文字聊天",
```

- [ ] **Step 4: Implement admin bill SQL additions**

In `backend/app/api/v1/app_users/app_users.py`, import/use `ImTextMessageChargeRecord` or raw SQL matching existing bill style. Add `im_text` to allowed types and append sender expense / receiver income rows with `asset_type` set to `coins` / `diamonds`.

- [ ] **Step 5: Run tests**

Run:

```bash
cd backend
pytest -q tests/test_im_text_billing.py
```

Expected: pass.

---

### Task 6: Flutter Charge Before Send

**Files:**
- Modify: `huanxi/lib/core/constants/api_endpoints.dart`
- Modify: `huanxi/lib/core/network/response_parsers.dart`
- Modify: `huanxi/lib/app/providers/auth_provider.dart`
- Modify: `huanxi/lib/modules/im/im_page.dart`
- Test: Flutter analyzer/manual verification

- [ ] **Step 1: Add endpoint and parser**

Modify `api_endpoints.dart`:

```dart
/// 文字消息发送前扣费
static const String imTextCharge = 'app/im/text-charge';
```

Add to `response_parsers.dart`:

```dart
class IMTextChargePayload {
  final bool charged;
  final int price;
  final int anchorIncomeDiamonds;
  final int coins;
  final int diamonds;
  final int receiverUserId;
  final String requestId;

  const IMTextChargePayload({
    required this.charged,
    required this.price,
    required this.anchorIncomeDiamonds,
    required this.coins,
    required this.diamonds,
    required this.receiverUserId,
    required this.requestId,
  });
}
```

Then add `parseIMTextChargePayload(dynamic rawResponse)` that mirrors `parseUserSigPayload`: require `data` map, parse bool/int/string fields, and throw `FormatException` if missing.

- [ ] **Step 2: Extend bootstrap state**

In `AppInitState`, add fields:

```dart
final bool imTextBillingEnabled;
final int imTextBillingPrice;
final int imTextBillingAnchorShareBps;
```

Default to `false`, `0`, `5000`; parse `respData['im_text_billing']` inside `AppInitNotifier.init()`.

- [ ] **Step 3: Add charge helper in IM page**

In `ImPage`, add:

```dart
String _newTextChargeRequestId({required int receiverUserId, required String text}) {
  return 'im_text_${DateTime.now().microsecondsSinceEpoch}_${receiverUserId}_${text.hashCode.abs()}';
}
```

Add:

```dart
Future<void> _chargeTextMessageIfNeeded({
  required int receiverUserId,
  required String requestId,
}) async {
  final response = await DioClient.instance.post(
    ApiEndpoints.imTextCharge,
    data: {
      'receiver_user_id': receiverUserId,
      'request_id': requestId,
    },
  );
  ResponseParsers.parseIMTextChargePayload(response.data);
}
```

- [ ] **Step 4: Call charge before SDK send**

Modify `_sendMessage()`:

```dart
final receiverUserId = _extractAppUserId(_peerUserId ?? widget.userId);
if (receiverUserId == null || receiverUserId <= 0) {
  AppToast.showSnackBar(context, const SnackBar(content: Text('聊天对象异常')));
  return;
}
final requestId = _newTextChargeRequestId(receiverUserId: receiverUserId, text: text);
await _chargeTextMessageIfNeeded(receiverUserId: receiverUserId, requestId: requestId);
final sentMsg = await _imService.sendTextMessage(...);
```

Catch `ApiException` code `501` and show `e.message` without calling SDK. Keep existing generic failure for SDK errors.

- [ ] **Step 5: Verify Flutter**

Run:

```bash
cd huanxi
flutter analyze
```

Expected: no new analyzer errors.

---

### Task 7: Admin Web UI

**Files:**
- Modify: `backend/web/src/api/system.js`
- Modify: `backend/web/src/api/index.js`
- Create: `backend/web/src/views/system/im-text-billing/index.vue`
- Modify: `backend/app/core/init_app.py`
- Test: frontend build/lint or targeted source contract test.

- [ ] **Step 1: Add source contract test**

Append to `backend/tests/test_im_text_billing.py`:

```python
def test_admin_web_im_text_billing_page_exists() -> None:
    api_content = _read_backend_file("web/src/api/system.js")
    page_content = _read_backend_file("web/src/views/system/im-text-billing/index.vue")

    assert "getIMTextBillingConfig" in api_content
    assert "updateIMTextBillingConfig" in api_content
    assert "文字聊天计费" in page_content
    assert "NInputNumber" in page_content
    assert "NSwitch" in page_content
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd backend
pytest -q tests/test_im_text_billing.py::test_admin_web_im_text_billing_page_exists
```

Expected: fail because page/API methods do not exist.

- [ ] **Step 3: Add API methods**

Modify `backend/web/src/api/system.js`:

```js
getIMTextBillingConfig: () => request.get('/apis/system/im-text-billing-config'),
updateIMTextBillingConfig: (data = {}) => request.put('/apis/system/im-text-billing-config', data),
```

- [ ] **Step 4: Create Vue page**

Create `backend/web/src/views/system/im-text-billing/index.vue` with a single `CommonPage`, `NForm`, `NSwitch`, `NInputNumber`, and save button. Use percent display for share:

```js
const sharePercent = computed({
  get: () => Number((Number(form.value.anchor_share_bps || 0) / 100).toFixed(2)),
  set: (value) => {
    const percent = Number(value)
    form.value.anchor_share_bps = Number.isFinite(percent)
      ? Math.min(10000, Math.max(0, Math.round(percent * 100)))
      : 5000
  },
})
```

Submit payload:

```js
{
  enabled: form.value.enabled,
  price: Number(form.value.price || 0),
  anchor_share_bps: Number(form.value.anchor_share_bps || 0),
}
```

- [ ] **Step 5: Verify backend source test and frontend**

Before verification, add a fresh-install menu entry in `backend/app/core/init_app.py` using the local helper/field names already present in that file. Keep the route path and component path exactly `/system/im-text-billing`; use menu name `文字聊天计费` and an existing chat/settings icon style.

Run:

```bash
cd backend
pytest -q tests/test_im_text_billing.py::test_admin_web_im_text_billing_page_exists
cd web
pnpm lint
```

Expected: pytest passes; lint passes or report existing unrelated lint failures.

---

### Task 8: Full Verification

**Files:**
- All modified files.

- [ ] **Step 1: Run backend focused tests**

Run:

```bash
cd backend
pytest -q tests/test_im_text_billing.py tests/test_atomic_balance_field_usage.py tests/test_dual_currency_contract.py
```

Expected: pass.

- [ ] **Step 2: Run backend lint**

Run:

```bash
cd backend
ruff check ./app
```

Expected: pass.

- [ ] **Step 3: Run Flutter analyzer**

Run:

```bash
cd huanxi
flutter analyze
```

Expected: pass or only pre-existing unrelated warnings; document exact output.

- [ ] **Step 4: Run admin web verification**

Run:

```bash
cd backend/web
pnpm lint
```

Expected: pass or only pre-existing unrelated warnings; document exact output.

- [ ] **Step 5: Review diff**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only intended files modified.
