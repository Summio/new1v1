# 我的钱包页面实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新建「我的钱包」页面（含余额展示、提现申请、账单明细 Tab），同时调整 Profile 页面的余额卡片交互和菜单入口。

**Architecture:** 前端新建 `wallet_page.dart` + `withdraw_sheet.dart` + `wallet_provider.dart`；后端新增 `/wallet/transactions` 接口；Profile 页面余额卡片改为可点击区域。

**Tech Stack:** Flutter (Riverpod / go_router / Dio), FastAPI (Tortoise ORM / Pydantic)

---

## 文件清单

| 文件 | 操作 | 职责 |
|------|------|------|
| `backend/app/schemas/app_api.py` | 修改 | 新增 TransactionRecord、TransactionListOut |
| `backend/app/api/v1/app/wallet.py` | 修改 | 新增 `/wallet/transactions` 接口 |
| `huanxi/lib/app/routes/app_router.dart` | 修改 | 注册 `/wallet` 路由 |
| `huanxi/lib/app/providers/wallet_provider.dart` | 新建 | 钱包状态管理 + 账单请求 |
| `huanxi/lib/modules/home/wallet_page.dart` | 新建 | 钱包页面（含余额卡片 + Tab 明细 + 提现按钮） |
| `huanxi/lib/modules/home/withdraw_sheet.dart` | 新建 | 提现表单底部弹窗组件 |
| `huanxi/lib/modules/home/profile_page.dart` | 修改 | 余额卡片可点击 + 菜单调整 |

---

## Task 1: 后端 — 新增账单明细 Schema

**Files:**
- Modify: `D:/1v1/new1v1/backend/app/schemas/app_api.py`

- [ ] **Step 1: 添加 TransactionRecord 和 TransactionListOut schema**

在 `app_api.py` 末尾（`IMSigOut` 之前）添加：

```python
# ===== Wallet Transactions =====

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

- [ ] **Step 2: 验证 import**

确保文件顶部已有 `from typing import List`，如有需要补充。

Run: `./venv/Scripts/python -c "from app.schemas.app_api import TransactionRecord, TransactionListOut; print('OK')"`
Expected: OK

- [ ] **Step 3: Commit**

```bash
cd D:/1v1/new1v1/backend
git add app/schemas/app_api.py
git commit -m "feat(wallet): add TransactionRecord and TransactionListOut schemas"
```

---

## Task 2: 后端 — 新增账单明细接口

**Files:**
- Modify: `D:/1v1/new1v1/backend/app/api/v1/app/wallet.py`

- [ ] **Step 1: 在 wallet.py 顶部添加 Response 字段**

在文件顶部的 `router = APIRouter()` 前添加 `Optional` import 和 `List` import（如果尚未导入的话），然后在 `WithdrawApplyOut` schema 之后添加 `TransactionRecord` 和 `TransactionListOut` 的 import（注意避免循环导入）。实际上，由于 schema 已在 `app_api.py` 中定义，只需在该文件顶部已有的 `from app.schemas.app_api import ...` 行中添加新 schema 即可。

确认 `app_api.py` 的 import 行包含：
```python
from app.schemas.app_api import (
    BalanceOut,
    RechargeCreateIn,
    RechargeCreateOut,
    WithdrawApplyIn,
    WithdrawApplyOut,
    TransactionRecord,       # 新增
    TransactionListOut,        # 新增
)
```

- [ ] **Step 2: 在 wallet.py 中添加 /transactions 接口**

在 `wallet.py` 末尾（`WithdrawApplyOut` 之后）添加：

```python
@router.get("/wallet/transactions", summary="账单明细", dependencies=[DependAppAuth])
async def wallet_transactions(type: str = "all", page: int = 1, page_size: int = 20):
    user_id = CTX_APP_USER_ID.get()

    all_records = []

    # 充值记录（收入）
    recharges = await RechargeOrder.filter(user_id=user_id, status="paid").all().order_by("-created_at")
    for r in recharges:
        all_records.append(TransactionRecord(
            id=str(r.id),
            type="recharge",
            title="充值",
            amount=r.amount,
            is_income=True,
            created_at=r.created_at.strftime("%Y-%m-%d %H:%M:%S") if r.created_at else "",
        ))

    # 通话记录（支出）
    calls = await CallRecord.filter(user_id=user_id).all().order_by("-created_at")
    for c in calls:
        all_records.append(TransactionRecord(
            id=str(c.id),
            type="call",
            title="通话消费",
            amount=c.duration * 10,  # 假设 10 钻石/分钟，按实际配置调整
            is_income=False,
            created_at=c.created_at.strftime("%Y-%m-%d %H:%M:%S") if c.created_at else "",
        ))

    # 送礼记录（支出）
    gifts = await GiftRecord.filter(user_id=user_id).all().order_by("-created_at")
    for g in gifts:
        all_records.append(TransactionRecord(
            id=str(g.id),
            type="gift",
            title="送礼物",
            amount=g.amount,
            is_income=False,
            created_at=g.created_at.strftime("%Y-%m-%d %H:%M:%S") if g.created_at else "",
        ))

    # 提现申请（支出）
    withdraws = await WithdrawApply.filter(user_id=user_id).all().order_by("-created_at")
    for w in withdraws:
        all_records.append(TransactionRecord(
            id=str(w.id),
            type="withdraw",
            title="提现申请",
            amount=w.amount,
            is_income=False,
            created_at=w.created_at.strftime("%Y-%m-%d %H:%M:%S") if w.created_at else "",
        ))

    # 按时间倒序
    all_records.sort(key=lambda x: x.created_at, reverse=True)

    # 按 type 过滤
    if type == "income":
        all_records = [r for r in all_records if r.is_income]
    elif type == "expense":
        all_records = [r for r in all_records if not r.is_income]

    # 分页
    total = len(all_records)
    start = (page - 1) * page_size
    end = start + page_size
    page_records = all_records[start:end]

    return Success(data=TransactionListOut(
        records=page_records,
        total=total,
        current=page,
        has_more=end < total,
    ).model_dump())
```

> 注意：`CallRecord.duration * 10` 中的单价按实际通话费率填写。先用 10 作为占位值，后续按需调整。

- [ ] **Step 3: 添加 CallRecord 和 GiftRecord 的 import**

在 `wallet.py` 顶部的 `from app.models import AppUser, RechargeOrder, WithdrawApply` 改为：

```python
from app.models import AppUser, CallRecord, GiftRecord, RechargeOrder, WithdrawApply
```

- [ ] **Step 4: 验证接口可启动**

Run: `./venv/Scripts/python -c "from app.api.v1.app.wallet import router; print('wallet router OK')"`
Expected: wallet router OK

- [ ] **Step 5: Commit**

```bash
cd D:/1v1/new1v1/backend
git add app/api/v1/app/wallet.py
git commit -m "feat(wallet): add /wallet/transactions API for billing history"
```

---

## Task 3: 前端 — 注册路由

**Files:**
- Modify: `D:/1v1/new1v1/huanxi/lib/app/routes/app_router.dart`

- [ ] **Step 1: 添加 WalletPage import**

在顶部的 import 区域添加：

```dart
import '../../modules/home/wallet_page.dart';
```

- [ ] **Step 2: 添加 wallet 路由常量**

在 `AppRoutes` 类中的 `recharge` 之后添加：

```dart
static const String wallet = '/wallet';
```

- [ ] **Step 3: 添加 GoRoute**

在 `routes` 列表中（`RechargePage` 路由之后）添加：

```dart
GoRoute(path: AppRoutes.wallet, builder: (context, state) => const WalletPage()),
```

- [ ] **Step 4: Commit**

```bash
cd D:/1v1/new1v1/huanxi
git add lib/app/routes/app_router.dart
git commit -m "feat(wallet): register /wallet route"
```

---

## Task 4: 前端 — 创建钱包状态管理 Provider

**Files:**
- Create: `D:/1v1/new1v1/huanxi/lib/app/providers/wallet_provider.dart`

- [ ] **Step 1: 创建 wallet_provider.dart**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../core/constants/api_endpoints.dart';
import 'auth_provider.dart';

// ========== Types ==========

enum TransactionType { all, income, expense }

class TransactionRecord {
  final String id;
  final String type;
  final String title;
  final int amount;
  final bool isIncome;
  final String createdAt;

  TransactionRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.amount,
    required this.isIncome,
    required this.createdAt,
  });

  factory TransactionRecord.fromJson(Map<String, dynamic> json) {
    return TransactionRecord(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      title: json['title'] ?? '',
      amount: json['amount'] ?? 0,
      isIncome: json['is_income'] ?? false,
      createdAt: json['created_at'] ?? '',
    );
  }
}

class TransactionListState {
  final List<TransactionRecord> records;
  final int total;
  final int current;
  final bool hasMore;
  final bool isLoading;
  final String? error;

  TransactionListState({
    this.records = const [],
    this.total = 0,
    this.current = 1,
    this.hasMore = false,
    this.isLoading = false,
    this.error,
  });

  TransactionListState copyWith({
    List<TransactionRecord>? records,
    int? total,
    int? current,
    bool? hasMore,
    bool? isLoading,
    String? error,
  }) {
    return TransactionListState(
      records: records ?? this.records,
      total: total ?? this.total,
      current: current ?? this.current,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// ========== Notifier ==========

class WalletNotifier extends StateNotifier<TransactionListState> {
  WalletNotifier() : super(TransactionListState());

  Future<void> loadTransactions({TransactionType type = TransactionType.all, int page = 1}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final typeStr = type == TransactionType.all ? 'all' : (type == TransactionType.income ? 'income' : 'expense');
      final res = await DioClient.instance.apiGet(
        ApiEndpoints.walletTransactions,
        queryParameters: {'type': typeStr, 'page': page, 'page_size': 20},
      );
      final data = res['data'] as Map<String, dynamic>;
      final records = (data['records'] as List)
          .map((e) => TransactionRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      state = TransactionListState(
        records: records,
        total: data['total'] ?? 0,
        current: data['current'] ?? 1,
        hasMore: data['has_more'] ?? false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> withdraw({
    required int amount,
    required String alipayAccount,
    required String realName,
  }) async {
    try {
      await DioClient.instance.apiPost(ApiEndpoints.withdrawApply, data: {
        'amount': amount,
        'bank_name': '支付宝',
        'account_no': alipayAccount,
        'real_name': realName,
      });
      // Refresh balance
      await DioClient.instance.apiGet(ApiEndpoints.walletBalance);
      return true;
    } catch (e) {
      return false;
    }
  }
}

// ========== Provider ==========

final walletProvider = StateNotifierProvider<WalletNotifier, TransactionListState>((ref) {
  return WalletNotifier();
});
```

- [ ] **Step 2: 在 api_endpoints.dart 中添加 walletTransactions 常量**

检查 `D:/1v1/new1v1/huanxi/lib/core/constants/api_endpoints.dart`，在末尾添加：

```dart
/// 钱包账单明细
static const String walletTransactions = 'app/wallet/transactions';
```

- [ ] **Step 3: Commit**

```bash
cd D:/1v1/new1v1/huanxi
git add lib/app/providers/wallet_provider.dart lib/core/constants/api_endpoints.dart
git commit -m "feat(wallet): add WalletProvider for state management and transaction API"
```

---

## Task 5: 前端 — 创建提现弹窗组件

**Files:**
- Create: `D:/1v1/new1v1/huanxi/lib/modules/home/withdraw_sheet.dart`

- [ ] **Step 1: 创建 withdraw_sheet.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers/wallet_provider.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/theme/app_theme.dart';

class WithdrawSheet extends ConsumerStatefulWidget {
  const WithdrawSheet({super.key});

  @override
  ConsumerState<WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends ConsumerState<WithdrawSheet> {
  final _amountController = TextEditingController();
  final _alipayController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    _alipayController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amountText = _amountController.text.trim();
    final alipay = _alipayController.text.trim();
    final name = _nameController.text.trim();

    if (amountText.isEmpty || alipay.isEmpty || name.isEmpty) {
      _showError('请填写完整信息');
      return;
    }

    final amount = int.tryParse(amountText);
    if (amount == null || amount < 100) {
      _showError('提现金额最低 100 钻石');
      return;
    }

    setState(() => _isLoading = true);

    final ok = await ref.read(walletProvider.notifier).withdraw(
          amount: amount,
          alipayAccount: alipay,
          realName: name,
        );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (ok) {
      // Refresh balance in auth state
      final balanceRes = await ref.read(authProvider.notifier).fetchBalance();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提现申请已提交')),
      );
      // Refresh transactions
      ref.read(walletProvider.notifier).loadTransactions();
    } else {
      _showError('提现失败，请重试');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.errorColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final diamonds = ref.watch(authProvider).diamonds;

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('申请提现', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textHint),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('可提现钻石: $diamonds', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 20),

          // 提现金额
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: '提现金额（钻石）',
              hintText: '最低 100 钻石',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.diamond_outlined),
            ),
          ),
          const SizedBox(height: 16),

          // 支付宝账号
          TextField(
            controller: _alipayController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: '支付宝账号',
              hintText: '请输入支付宝账号',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
            ),
          ),
          const SizedBox(height: 16),

          // 真实姓名
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: '真实姓名',
              hintText: '请输入真实姓名',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 24),

          // 提示
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warningColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '提现仅支持支付宝，预计 1-3 个工作日到账',
              style: TextStyle(fontSize: 12, color: AppTheme.warningColor),
            ),
          ),
          const SizedBox(height: 20),

          // 确认按钮
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.secondaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('确认提现', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 在 auth_provider.dart 中添加 fetchBalance 方法**

检查 `D:/1v1/new1v1/huanxi/lib/app/providers/auth_provider.dart`，确认已有 `fetchBalance` 或类似方法。如果没有，在 `AuthNotifier` 中添加：

```dart
Future<void> fetchBalance() async {
  try {
    final res = await DioClient.instance.apiGet(ApiEndpoints.walletBalance);
    final data = res['data'] as Map<String, dynamic>;
    state = state.copyWith(
      coins: data['coins'] ?? state.coins,
      diamonds: data['diamonds'] ?? state.diamonds,
    );
  } catch (_) {}
}
```

如果方法已存在则跳过此步骤。

- [ ] **Step 3: Commit**

```bash
cd D:/1v1/new1v1/huanxi
git add lib/modules/home/withdraw_sheet.dart
git commit -m "feat(wallet): add WithdrawSheet bottom sheet component"
```

---

## Task 6: 前端 — 创建钱包页面

**Files:**
- Create: `D:/1v1/new1v1/huanxi/lib/modules/home/wallet_page.dart`

- [ ] **Step 1: 创建 wallet_page.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers/auth_provider.dart';
import '../../app/providers/wallet_provider.dart';
import '../../app/theme/app_theme.dart';
import 'withdraw_sheet.dart';

class WalletPage extends ConsumerStatefulWidget {
  const WalletPage({super.key});

  @override
  ConsumerState<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends ConsumerState<WalletPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  TransactionType _currentType = TransactionType.all;

  final _typeLabels = ['全部', '收入', '支出'];
  final _typeValues = [TransactionType.all, TransactionType.income, TransactionType.expense];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    // 初始加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(walletProvider.notifier).loadTransactions(type: TransactionType.all);
    });
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final type = _typeValues[_tabController.index];
    if (type != _currentType) {
      _currentType = type;
      ref.read(walletProvider.notifier).loadTransactions(type: type);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showWithdrawSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const WithdrawSheet(),
    );
  }

  IconData _getRecordIcon(String type) {
    switch (type) {
      case 'recharge': return Icons.account_balance_wallet;
      case 'call': return Icons.video_call;
      case 'gift': return Icons.card_giftcard;
      case 'withdraw': return Icons.payments;
      default: return Icons.receipt;
    }
  }

  Color _getRecordIconColor(String type) {
    switch (type) {
      case 'recharge': return const Color(0xFF34C759);
      case 'call': return const Color(0xFF5856D6);
      case 'gift': return const Color(0xFFFF2D55);
      case 'withdraw': return const Color(0xFFFF9500);
      default: return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final tokenNames = ref.watch(tokenNamesProvider);
    final txState = ref.watch(walletProvider);
    final isAnchor = authState.appRole == 'anchor';

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('我的钱包', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: Column(
        children: [
          // ===== 余额卡片 =====
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppTheme.balanceGradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppTheme.elevatedShadow,
            ),
            child: isAnchor
                ? _buildAnchorBalance(authState)
                : _buildUserBalance(authState, tokenNames),
          ),

          // ===== 申请提现按钮（仅主播）=====
          if (isAnchor) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _showWithdrawSheet,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9500),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('申请提现', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ===== 账单明细标题 =====
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('账单明细', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== Tab Bar =====
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: AppTheme.cardShadow,
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: AppTheme.primaryColor,
              unselectedLabelColor: AppTheme.textSecondary,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              dividerColor: Colors.transparent,
              tabs: _typeLabels.map((l) => Tab(text: l)).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // ===== 列表 =====
          Expanded(
            child: txState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : txState.error != null
                    ? Center(child: Text('加载失败: ${txState.error}', style: const TextStyle(color: AppTheme.errorColor)))
                    : txState.records.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.receipt_long_outlined, size: 64, color: AppTheme.textHint),
                                SizedBox(height: 12),
                                Text('暂无记录', style: TextStyle(color: AppTheme.textHint, fontSize: 15)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: txState.records.length,
                            itemBuilder: (context, index) {
                              final record = txState.records[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: AppTheme.cardShadow,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: _getRecordIconColor(record.type).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(_getRecordIcon(record.type), color: _getRecordIconColor(record.type), size: 22),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(record.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                                          const SizedBox(height: 2),
                                          Text(record.createdAt, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '${record.isIncome ? '+' : '-'}${record.amount}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: record.isIncome ? const Color(0xFF34C759) : AppTheme.errorColor,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      record.isIncome ? '钻石' : '钻石',
                                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildUserBalance(AuthState authState, TokenNamesState tokenNames) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${tokenNames.coinName}余额', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Text(authState.coins.toString(), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${tokenNames.diamondName}余额', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Text(authState.diamonds.toString(), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnchorBalance(AuthState authState) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('累计收益 (元)', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Text((authState.coins / 100).toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('钻石余额', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Text(authState.diamonds.toString(), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
cd D:/1v1/new1v1/huanxi
git add lib/modules/home/wallet_page.dart
git commit -m "feat(wallet): add WalletPage with balance display, tab history, and withdraw button"
```

---

## Task 7: 前端 — 调整 Profile 页面

**Files:**
- Modify: `D:/1v1/new1v1/huanxi/lib/modules/home/profile_page.dart`

需要改动两个地方：

### 改动 A：余额卡片改为可点击区域

将 `_buildUserBalance` 方法内的 Column（金币和钻石余额列）各自包一层 GestureDetector。

将：
```dart
Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${tokenNames.coinName}余额', ...),
      const SizedBox(height: 8),
      Text(authState.coins.toString(), ...),
    ],
  ),
),
```

改为：
```dart
Expanded(
  child: GestureDetector(
    onTap: () => context.push(AppRoutes.recharge),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${tokenNames.coinName}余额', ...),
        const SizedBox(height: 8),
        Text(authState.coins.toString(), ...),
      ],
    ),
  ),
),
Expanded(
  child: GestureDetector(
    onTap: () => context.push(AppRoutes.wallet),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${tokenNames.diamondName}余额', ...),
        const SizedBox(height: 8),
        Text(authState.diamonds.toString(), ...),
      ],
    ),
  ),
),
```

同时移除 `Row` 末尾的"立即充值"按钮。

### 改动 B：菜单列表

将原来的：
```dart
_buildMenuTile(..., title: '我的钱包', iconColor: const Color(0xFFFF9500), onTap: () => context.push(AppRoutes.recharge)),
```

改为：
```dart
_buildMenuTile(icon: Icons.account_balance_wallet_rounded, title: '我的钱包', iconColor: const Color(0xFFFF9500), onTap: () => context.push(AppRoutes.wallet)),
_buildMenuTile(icon: Icons.add_circle_rounded, title: '充值', iconColor: const Color(0xFF5856D6), onTap: () => context.push(AppRoutes.recharge)),
```

- [ ] **Step 1: 修改 profile_page.dart — 余额卡片可点击**

将 `_buildUserBalance` 方法中金币余额和钻石余额的 Column 各自包 GestureDetector，并移除"立即充值"按钮（从 Row 的 children 中删除）。

- [ ] **Step 2: 修改 profile_page.dart — 菜单列表**

将「我的钱包」的跳转目标从 `AppRoutes.recharge` 改为 `AppRoutes.wallet`，并新增「充值」菜单项跳 `AppRoutes.recharge`。

- [ ] **Step 3: 修改 profile_page.dart — 主播余额卡片**

在 `_buildAnchorBalance` 方法中，钻石余额区域同样包 GestureDetector → `context.push(AppRoutes.wallet)`。累计收益区域保持不点击。

- [ ] **Step 4: Commit**

```bash
cd D:/1v1/new1v1/huanxi
git add lib/modules/home/profile_page.dart
git commit -m "feat(profile): make balance card clickable and update menu items"
```

---

## Task 8: 端到端验证

- [ ] **Step 1: 启动后端**

```bash
cd D:/1v1/new1v1/backend && make run
```

确认无报错，`/wallet/transactions` 接口可访问。

- [ ] **Step 2: 启动 Flutter**

```bash
cd D:/1v1/new1v1/huanxi && flutter run
```

- [ ] **Step 3: 测试流程**

1. 登录 → 进入「我的」页面 → 点击金币余额区域 → 应跳转到充值页
2. 点击钻石余额区域 → 应跳转到钱包页 `/wallet`
3. 在钱包页 → 查看余额展示 → 点击「申请提现」→ 弹窗出现
4. 填写信息提交 → 余额应更新
5. 切换 Tab → 账单明细应正确过滤
6. Profile 页面 → 点击「我的钱包」→ 应跳 `/wallet`；点击「充值」→ 应跳 `/recharge`

---

## 自检清单

- [ ] 所有 Schema 类型与接口响应字段一致
- [ ] `TransactionRecord.type` 映射：`recharge`/`call`/`gift`/`withdraw`
- [ ] `is_income` 字段正确：`recharge=true`，其余为 `false`
- [ ] `wallet_page.dart` 中 Tab 与 `TransactionType` 枚举顺序对应
- [ ] `profile_page.dart` 中金币 → `/recharge`，钻石 → `/wallet`
- [ ] 提现弹窗的 `bank_name` 固定传 `"支付宝"`
