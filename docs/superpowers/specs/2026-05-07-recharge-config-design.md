# 充值配置功能设计

**日期：** 2026-05-07  
**状态：** 待实现

## 一、概述

为欢喜平台增加完整的充值配置系统，允许运营人员通过管理后台动态配置充值套餐，配置通过后端接口下发给 Flutter 客户端。

### 目标

- 管理后台可视化配置充值套餐（金额、金币数、标签、角标）
- 后端 `bootstrap` 接口返回充值配置给客户端
- 客户端无需更新即可使用新配置
- 配置变更实时生效（60秒缓存过期后）

### 非目标

- 不支持充值套餐历史版本管理
- 不支持 A/B 测试或用户分组
- 不支持套餐生效时间控制

## 二、架构设计

### 数据流向

```
管理后台 → PUT /recharge-config → system_config 表 → 清除 Redis 缓存
                                         ↓
Flutter 客户端 → GET /bootstrap → 读取配置 + Redis 缓存 → 返回套餐列表
```

### 核心组件

1. **数据存储**：`system_config` 表
   - 新增配置项：`recharge_packages`（JSON 字符串）
   - 复用现有的 Redis 缓存机制（60秒 TTL）

2. **后端接口**：
   - 修改：`GET /api/v1/app/init/bootstrap` 返回充值配置
   - 新增：`GET /api/v1/apis/system/recharge-config` 获取配置（管理端）
   - 新增：`PUT /api/v1/apis/system/recharge-config` 更新配置（管理端）

3. **管理后台**：新增"充值配置"页面

4. **客户端**：无需修改（已支持从 bootstrap 读取配置）

## 三、数据模型设计

### system_config 表新增配置项

| cfg_key | cfg_value 示例 | description |
|---------|---------------|-------------|
| recharge_packages | JSON 字符串（见下方） | 充值套餐列表 |

### recharge_packages JSON 格式

```json
[
  {
    "amount": 6,
    "coins": 60,
    "label": "6元",
    "tag": "尝鲜"
  },
  {
    "amount": 9.9,
    "coins": 100,
    "label": "9.9元",
    "tag": "推荐"
  },
  {
    "amount": 30,
    "coins": 350,
    "label": "30元",
    "tag": "特惠"
  }
]
```

### 字段说明

- `amount`：充值金额（元，支持小数，如 9.9）
- `coins`：获得金币数（整数）
- `label`：显示标签（必填，1-20字符）
- `tag`：角标文字（可选，最多10字符，如"推荐"、"特惠"）

### 缓存策略

- 复用 `SystemConfig.get_all_as_dict()` 的 Redis 缓存（60秒 TTL）
- 更新配置时清除缓存键 `system_config:all`
- 客户端如果后端未配置，使用硬编码的默认套餐兜底

## 四、接口设计

### 4.1 修改现有接口

**`GET /api/v1/app/init/bootstrap`**

修改返回结构，新增 `recharge_packages` 字段：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "token_names": {
      "coin_name": "金币",
      "diamond_name": "钻石"
    },
    "im": { "configured": true, "sdk_app_id": 123456 },
    "rtc": { "configured": true },
    "call": { 
      "reject_inbound_protect_seconds": 5,
      "reject_pair_protect_seconds": 5
    },
    "recharge_packages": [
      {
        "amount": 6,
        "coins": 60,
        "label": "6元",
        "tag": "尝鲜"
      },
      {
        "amount": 30,
        "coins": 300,
        "label": "30元",
        "tag": "推荐"
      }
    ]
  }
}
```

**实现要点：**
- 从 `system_config` 读取 `recharge_packages` 配置
- JSON 解析失败时返回空数组 `[]`
- 客户端会使用默认套餐兜底

### 4.2 新增管理端接口

**`GET /api/v1/apis/system/recharge-config`**

获取当前充值配置。

- **权限**：需要管理员登录
- **请求**：无参数
- **响应**：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "packages": [
      {"amount": 6, "coins": 60, "label": "6元", "tag": "尝鲜"},
      {"amount": 30, "coins": 300, "label": "30元", "tag": "推荐"}
    ]
  }
}
```

**`PUT /api/v1/apis/system/recharge-config`**

更新充值配置。

- **权限**：需要管理员登录
- **请求体**：

```json
{
  "packages": [
    {"amount": 6, "coins": 60, "label": "6元", "tag": "尝鲜"},
    {"amount": 30, "coins": 300, "label": "30元", "tag": "推荐"}
  ]
}
```

- **校验规则**：
  - `amount` 必须 > 0（支持小数）
  - `coins` 必须 > 0 且为整数
  - `label` 必填，1-20字符
  - `tag` 可选，最多10字符
  - 套餐数量限制：1-20 个

- **响应**：

```json
{
  "code": 200,
  "msg": "配置已更新"
}
```

- **副作用**：清除 Redis 缓存 `system_config:all`

## 五、管理后台前端设计

### 页面路径

`backend/web/src/views/system/recharge-config/index.vue`

### 页面布局

```
┌─────────────────────────────────────┐
│ 充值配置                             │
├─────────────────────────────────────┤
│                                     │
│ 充值套餐配置                         │
│ ┌─────────────────────────────────┐ │
│ │ 套餐1  [6元]  [60金币]  [尝鲜]  │ │
│ │        [删除] [上移] [下移]      │ │
│ ├─────────────────────────────────┤ │
│ │ 套餐2  [30元] [300金币] [推荐]  │ │
│ │        [删除] [上移] [下移]      │ │
│ └─────────────────────────────────┘ │
│                                     │
│ [+ 添加套餐]                        │
│                                     │
│ [保存配置]  [重置]                  │
└─────────────────────────────────────┘
```

### 功能特性

1. **套餐列表**：动态表单，支持增删改
2. **排序调整**：支持上移/下移调整套餐顺序
3. **实时校验**：
   - 金额必须 > 0，支持小数（如 9.9）
   - 金币必须 > 0 的整数
   - 标签必填，1-20字符
   - 角标可选，最多10字符
4. **操作按钮**：
   - 保存：提交到后端并刷新
   - 重置：恢复到上次保存的状态
5. **提示信息**：保存成功后提示"配置已更新，客户端将在60秒内生效"

### 技术栈

- Vue 3 Composition API
- Naive UI 组件库（NForm, NInput, NButton, NCard, NInputNumber）
- 复用项目现有的 `CommonPage` 布局

## 六、实现细节

### 6.1 后端实现

**bootstrap.py 修改：**

```python
# 读取充值套餐配置
recharge_packages_raw = config_map.get("recharge_packages") or "[]"
try:
    recharge_packages = json.loads(recharge_packages_raw)
    if not isinstance(recharge_packages, list):
        recharge_packages = []
except:
    recharge_packages = []

# 返回数据中添加
return Success(data={
    "token_names": {...},
    "im": {...},
    "rtc": {...},
    "call": {...},
    "recharge_packages": recharge_packages
})
```

**新增 system/recharge_config.py：**

- 路由：`/api/v1/apis/system/recharge-config`
- 依赖：需要管理员权限（复用现有的 `get_current_user` 依赖）
- GET：读取 `system_config` 表，解析 JSON
- PUT：校验数据 → 更新/插入 `system_config` → 清除 Redis 缓存

**数据校验（Pydantic Schema）：**

```python
class RechargePackageItem(BaseModel):
    amount: float = Field(gt=0, description="充值金额")
    coins: int = Field(gt=0, description="获得金币")
    label: str = Field(min_length=1, max_length=20)
    tag: Optional[str] = Field(None, max_length=10)

class RechargeConfigIn(BaseModel):
    packages: List[RechargePackageItem] = Field(min_length=1, max_length=20)
```

### 6.2 前端实现

**状态管理：**

```javascript
const packages = ref([])  // 套餐列表
const loading = ref(false)
const saving = ref(false)
const originalPackages = ref([])  // 用于重置
```

**核心方法：**

- `fetchConfig()`：加载配置
- `addPackage()`：添加空套餐
- `removePackage(index)`：删除套餐
- `moveUp(index)` / `moveDown(index)`：调整顺序
- `saveConfig()`：提交保存
- `resetConfig()`：重置表单

**表单校验：**

- 使用 Naive UI 的 `NForm` + `rules` 进行前端校验
- 金额：正数，最多2位小数
- 金币：正整数
- 标签：必填，1-20字符
- 角标：可选，最多10字符

## 七、错误处理与边界情况

### 7.1 后端错误处理

**配置读取失败：**
- JSON 解析失败时返回空数组 `[]`
- 客户端使用硬编码默认套餐兜底

**配置更新失败：**
- 数据库写入失败：返回 500 错误，提示"配置保存失败"
- Redis 缓存清除失败：记录日志但不影响主流程（缓存会在60秒后自动过期）

**权限校验：**
- 未登录：返回 401
- 非管理员：返回 403

### 7.2 前端错误处理

**加载失败：**
- 显示错误提示："加载配置失败，请刷新重试"
- 保留空表单，允许用户手动添加

**保存失败：**
- 显示后端返回的错误信息
- 表单数据保留，允许修改后重试

**网络超时：**
- 显示友好提示："网络超时，请检查连接"

### 7.3 边界情况

**空配置：**
- 后端允许保存空数组（客户端会使用默认套餐）
- 前端至少要求1个套餐才能保存

**重复套餐：**
- 不做唯一性校验（允许配置相同金额的不同套餐）

**历史订单兼容：**
- 修改套餐配置不影响已创建的充值订单
- `RechargeOrder` 表存储的是实际金额，与套餐配置解耦

## 八、测试策略

### 8.1 后端测试

**单元测试（pytest）：**

```python
# 正常流程
test_get_recharge_config_success()
test_update_recharge_config_success()
test_bootstrap_returns_packages()

# 边界情况
test_update_empty_packages()
test_update_invalid_amount()
test_update_invalid_coins()
test_json_parse_error_fallback()

# 权限
test_recharge_config_requires_auth()
```

### 8.2 前端测试

**手动测试清单：**

- [ ] 加载现有配置
- [ ] 添加新套餐
- [ ] 删除套餐
- [ ] 上移/下移套餐
- [ ] 保存配置成功
- [ ] 表单校验（空值、负数、非整数金币）
- [ ] 重置表单
- [ ] 网络错误处理

### 8.3 集成测试

**端到端流程：**

1. 管理后台配置充值套餐
2. 保存成功
3. 等待缓存过期（或手动清除 Redis）
4. Flutter 客户端调用 `bootstrap` 接口
5. 验证客户端显示新配置的套餐

## 九、部署与回滚

### 9.1 部署步骤

**1. 数据库初始化（可选）：**

```sql
-- 插入默认充值配置
INSERT INTO system_config (cfg_key, cfg_value, description) 
VALUES (
  'recharge_packages',
  '[{"amount":6,"coins":60,"label":"6元","tag":"尝鲜"},{"amount":30,"coins":300,"label":"30元","tag":"推荐"},{"amount":68,"coins":700,"label":"68元","tag":"特惠"}]',
  '充值套餐配置'
);
```

**2. 后端部署：**
- 部署新代码（无需数据库迁移）
- 重启后端服务
- 验证 `bootstrap` 接口返回充值配置

**3. 前端部署：**
- 构建管理后台前端
- 部署静态资源
- 验证"充值配置"页面可访问

**4. 客户端：**
- 无需更新（已支持从 bootstrap 读取配置）

### 9.2 回滚方案

**如果出现问题：**

1. **后端回滚**：回退代码，重启服务
2. **配置回滚**：通过管理后台或直接修改数据库恢复旧配置
3. **缓存清除**：手动清除 Redis 缓存 `system_config:all`

**影响范围：**
- 客户端有默认套餐兜底，配置异常不影响充值功能
- 最坏情况：客户端显示硬编码的默认套餐

### 9.3 监控建议

**关键指标：**
- `bootstrap` 接口响应时间
- 充值配置更新频率
- JSON 解析错误日志

## 十、总结

### 实现范围

**后端：**
- 修改 `bootstrap.py` 返回充值配置
- 新增 `system/recharge_config.py` 管理端接口
- 新增 Pydantic Schema 校验

**前端：**
- 新增 `views/system/recharge-config/index.vue` 配置页面
- 新增 API 方法（`getRechargeConfig`, `updateRechargeConfig`）

**数据库：**
- 无需迁移，仅在 `system_config` 表插入初始配置

### 预期收益

- 运营人员可自主调整充值套餐，无需发版
- 配置变更实时生效（60秒内）
- 客户端无需更新即可使用新配置

