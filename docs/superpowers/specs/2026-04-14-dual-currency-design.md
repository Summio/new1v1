# 双币种系统设计（金币 + 钻石）

## 背景

现有系统只有单一余额字段 `balance`（单位：分），充值和消费都使用该字段。用户反馈需要区分：
- **金币**：充值获得，用于消费（打电话、送礼物）
- **钻石**：主播收益，用于提现

代币名称（金币/钻石显示什么中文名）需由管理后台可配置。

---

## 一、数据库改动

### 1.1 新建 `system_config` 表

存储系统级配置（键值对），供 Admin 和 App 端共用。

```sql
CREATE TABLE `system_config` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `cfg_key` varchar(64) NOT NULL UNIQUE COMMENT '配置键',
  `cfg_value` varchar(255) NOT NULL COMMENT '配置值',
  `description` varchar(255) COMMENT '说明',
  `created_at` datetime(6) DEFAULT CURRENT_TIMESTAMP(6),
  `updated_at` datetime(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 初始数据
INSERT INTO system_config (cfg_key, cfg_value, description) VALUES
  ('coin_name', '金币', '代币名称-用于充值和消费'),
  ('diamond_name', '钻石', '代币名称-用于主播收益');
```

### 1.2 修改 `app_user` 表

```sql
ALTER TABLE app_user
  ADD COLUMN coins BIGINT DEFAULT 0 COMMENT '金币余额(分)',
  ADD COLUMN diamonds BIGINT DEFAULT 0 COMMENT '钻石余额(分)',
  ADD COLUMN frozen_diamonds BIGINT DEFAULT 0 COMMENT '冻结钻石(分)';

-- 数据迁移：现有 balance 全部迁移到 coins
UPDATE app_user SET coins = balance WHERE coins = 0 AND balance > 0;
```

### 1.3 迁移说明

- `balance` 字段保留（暂不删除），历史兼容
- 新充值/消费全部走 `coins`，新收益全部走 `diamonds`
- 数据迁移后，用户的现有余额显示为金币余额

---

## 二、API 改动

### 2.1 管理端 — 系统配置

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/apis/system-config` | 查询所有系统配置 |
| PUT | `/api/v1/apis/system-config/{key}` | 更新指定配置值 |

响应格式：
```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "coin_name": "金币",
    "diamond_name": "钻石"
  }
}
```

### 2.2 App 端 — 用户信息

`GET /api/v1/app/user/info` 响应新增字段：
```json
{
  "balance": 0,
  "coins": 6000,
  "diamonds": 3000,
  "frozen_balance": 0,
  "frozen_diamonds": 0,
  ...
}
```

### 2.3 App 端 — 钱包余额

`GET /api/v1/app/wallet/balance` 响应：
```json
{
  "coins": 6000,
  "diamonds": 3000,
  "frozen_balance": 0,
  "frozen_diamonds": 0,
  "coin_name": "金币",
  "diamond_name": "钻石"
}
```
> `coins` 和 `diamonds` 均为分单位（1分=0.01元），与 balance 保持一致

### 2.4 充值

`POST /api/v1/app/recharge/create` — 支付完成后：
- `app_user.coins += amount`（金币增加，分单位）
- 不再操作 `balance` 字段

### 2.5 通话扣费

- 扣减用户 `coins`（金币）
- 增加主播 `diamonds`（钻石），1:1 比例
- 原有 `balance` 相关逻辑保留（兼容旧数据）

### 2.6 送礼扣费

- 扣减用户 `coins`（金币）
- 增加主播 `diamonds`（钻石），1:1 比例

### 2.7 钻石提现（新接口）

`POST /api/v1/app/withdraw/diamonds` — 主播申请提取钻石：
- 冻结主播 `diamonds`
- 后台审核通过后，发放对应人民币
- 与现有 `balance` 提现流程一致

---

## 三、前端改动

### 3.1 代币名称

- App 端在获取用户信息时，一并获取 `coin_name` / `diamond_name`
- 所有涉及代币名称的文案动态读取，不再硬编码

### 3.2 "我的"页面

**余额卡片**展示：
```
┌─────────────────────────────────┐
│  金币余额           钻石余额     │
│  6,000            3,000        │
│  [充值]            [收益明细]    │
└─────────────────────────────────┘
```

- 金币区：`充值` 按钮 → 跳转充值页（我的钱包）
- 钻石区：`收益明细` 按钮 → 跳转收益页（待开发，暂无则灰显或隐藏）

### 3.3 充值页（我的钱包）

- 标题：`我的钱包`
- 说明文案：`1元 = 10 {coin_name}，{coin_name}用于拨打主播电话`
- 底部按钮：`立即支付 ¥{amount}`

---

## 四、实现顺序

1. **数据库**：新建 `system_config` 表，修改 `app_user` 表，执行数据迁移
2. **后端 Model**：`SystemConfig` 模型 + 更新 `AppUser` 模型
3. **后端 Admin API**：系统配置 CRUD
4. **后端 App API**：用户信息/钱包余额返回 coins/diamonds
5. **后端业务逻辑**：充值/通话/送礼改为操作 coins/diamonds
6. **前端**：读取代币名称，余额卡片双货币展示
7. **管理端**：添加系统配置菜单（可选，后续迭代）
8. **钻石提现接口**：后续迭代

---

## 五、风险与注意事项

1. **数据迁移**：现有用户的 `balance` 数据迁移到 `coins`，需确保迁移脚本正确执行
2. **兼容性**：旧版 App 仍使用 `balance` 字段，新版同时支持 `coins` 和 `balance`
3. **事务性**：充值/通话/送礼需保证原子性，避免 coins 扣减成功但 diamonds 增加失败
