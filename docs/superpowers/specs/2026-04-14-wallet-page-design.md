# 我的钱包页面设计

## 概述

新建独立的「我的钱包」页面 (`/wallet`)，同时调整「我的」页面的余额卡片交互和菜单入口。

---

## 一、Profile 页面改动

### 1.1 余额卡片 — 区域可点击

**普通用户：**

```
┌──────────────────────────────────────┐
│  金币余额           钻石余额          │
│  1,280 (可点击)     520 (可点击)      │
└──────────────────────────────────────┘
  点击金币 → /recharge    点击钻石 → /wallet
```

- 移除原有的「立即充值」按钮
- 金币余额区域（外层 GestureDetector）点击 → `/recharge`
- 钻石余额区域点击 → `/wallet`
- 参考现有 profile 页面的可点击头像区域样式（`GestureDetector` + `onTap`）

**主播用户：**

- 累计收益区域 — 不可点击，纯展示
- 钻石余额区域 — 可点击 → `/wallet`
- 移除「立即充值」按钮

### 1.2 菜单列表调整

移除原有的余额卡片内按钮后，菜单列表中新增独立的充值入口：

| 图标 | 标题 | 跳转 |
|------|------|------|
| wallet | 我的钱包 | `/wallet` |
| add_circle | 充值 | `/recharge` |

> 原来「我的钱包」跳 `/recharge`，现在修正为跳 `/wallet`；新增「充值」入口跳 `/recharge`。

---

## 二、新增钱包页面 `/wallet`

### 2.1 路由

```dart
static const String wallet = '/wallet';
GoRoute(path: AppRoutes.wallet, builder: (context, state) => const WalletPage()),
```

### 2.2 顶部余额卡片（纯展示，不响应点击）

**普通用户：**

| 金币余额 | 钻石余额 |
|----------|----------|
| 1,280 | 520 |

**主播用户：**

| 累计收益 (元) | 钻石余额 |
|---------------|----------|
| 328.50 | 1,200 |

卡片样式与 profile 页面保持一致（渐变背景、圆角）。

### 2.3 「申请提现」按钮

余额卡片下方，独立圆角按钮（橙色）。

点击 → 弹出底部提现表单弹窗。

### 2.4 提现弹窗

底部弹出表单（Bottomsheet 或 AlertDialog）：

- 提现金额（TextField，单位：钻石）
- 支付宝账号（TextField，placeholder: 请输入支付宝账号）
- 真实姓名（TextField，placeholder: 请输入真实姓名）
- 确认提现按钮

> 提现仅支持支付宝。提交调用 `POST /api/v1/app/withdraw/apply`。
> 后端字段映射：`bank_name = "支付宝"`，`account_no = 支付宝账号`，`real_name = 真实姓名`

提交后：
- 成功：关闭弹窗，刷新余额，重新加载账单列表
- 失败：显示错误提示

### 2.5 Tab 账单明细

页面下半部分为 Tab 切换：

| 全部 | 收入 | 支出 |

- **全部**：所有收支记录
- **收入**：type = recharge（充值）→ `+xxx 钻石`
- **支出**：type = call / gift / withdraw → `-xxx 钻石`

列表项格式：

```
[图标] 类型名称           时间
       +100 钻石  /  -50 钻石
```

- 收入项：绿色 `+`
- 支出项：红色 `-`

无记录时显示空状态。

---

## 三、后端 API

### 3.1 新增 `GET /api/v1/app/wallet/transactions`

**认证：** `DependAppAuth`（Bearer Token）

**Query 参数：**
- `type`: `all` | `income` | `expense`（默认 `all`）
- `page`: int（默认 1）
- `page_size`: int（默认 20）

**响应：**

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "records": [
      {
        "id": "xxx",
        "type": "recharge",
        "title": "充值",
        "amount": 100,
        "is_income": true,
        "created_at": "2026-04-10 10:00:00"
      },
      {
        "id": "xxx",
        "type": "call",
        "title": "通话消费",
        "amount": 50,
        "is_income": false,
        "created_at": "2026-04-11 20:30:00"
      }
    ],
    "total": 25,
    "current": 1,
    "has_more": true
  }
}
```

### 3.2 数据来源

聚合四张表，按 `created_at` 倒序：

| 来源表 | type | is_income | title |
|--------|------|-----------|-------|
| RechargeOrder | recharge | true | 充值 |
| CallRecord | call | false | 通话消费 |
| GiftRecord | gift | false | 送礼物 |
| WithdrawApply | withdraw | false | 提现申请 |

> `amount` 统一用钻石单位。CallRecord/GiftRecord 后端扣的是 diamonds 字段。

### 3.3 Schema

```python
class TransactionRecord(BaseModel):
    id: str
    type: str  # recharge / call / gift / withdraw
    title: str
    amount: int
    is_income: bool
    created_at: str

class TransactionListOut(BaseModel):
    records: List[TransactionRecord]
    total: int
    current: int
    has_more: bool
```

---

## 四、涉及文件

### 前端

- `lib/app/routes/app_router.dart` — 注册 `/wallet` 路由
- `lib/modules/home/profile_page.dart` — 余额卡片可点击 + 菜单调整
- `lib/modules/home/wallet_page.dart` — 新建钱包页面
- `lib/modules/home/withdraw_sheet.dart` — 新建提现弹窗组件
- `lib/app/providers/wallet_provider.dart` — 新建钱包状态管理

### 后端

- `app/schemas/app_api.py` — 新增 `TransactionRecord`、`TransactionListOut`
- `app/api/v1/app/wallet.py` — 新增 `/wallet/transactions` 接口

---

## 五、页面布局结构

```
WalletPage
├── BalanceCard (纯展示，和 profile 一致)
├── WithdrawButton ("申请提现")
├── TransactionHistorySection
│   ├── TabBar (全部 / 收入 / 支出)
│   └── ListView.builder (TransactionItem)
└── WithdrawBottomSheet (弹窗)
```
