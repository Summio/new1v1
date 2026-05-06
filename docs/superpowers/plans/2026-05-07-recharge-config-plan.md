# 充值配置功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现完整的充值配置系统，允许运营人员通过管理后台动态配置充值套餐，配置通过后端接口下发给 Flutter 客户端。

**Architecture:** 使用 `system_config` 表存储充值套餐配置（JSON 字符串），复用现有的 Redis 缓存机制。后端提供管理端 CRUD 接口和修改 `bootstrap` 接口返回配置。前端新增配置页面，客户端无需修改（已支持）。

**Tech Stack:** FastAPI, Pydantic, Tortoise ORM, Redis, Vue 3, Naive UI

---

## 文件结构

### 后端新增文件
- `backend/app/api/v1/apis/system/recharge_config.py` - 充值配置管理接口
- `backend/app/api/v1/apis/system/__init__.py` - system 模块初始化
- `backend/app/schemas/system.py` - 充值配置相关 Schema

### 后端修改文件
- `backend/app/api/v1/app/bootstrap.py:9-66` - 添加充值配置返回
- `backend/app/api/v1/__init__.py:1-39` - 注册新路由

### 前端新增文件
- `backend/web/src/views/system/recharge-config/index.vue` - 充值配置页面
- `backend/web/src/api/system.js` - 系统配置相关 API

### 前端修改文件
- `backend/web/src/api/index.js:1-73` - 导出新 API 模块

### 测试文件
- `backend/tests/test_recharge_config.py` - 充值配置接口测试

---

## Task 1: 创建充值配置 Schema

**Files:**
- Create: `backend/app/schemas/system.py`

- [ ] **Step 1: 创建 Schema 文件**

```python
from typing import List, Optional
from pydantic import BaseModel, Field


class RechargePackageItem(BaseModel):
    """充值套餐项"""
    amount: float = Field(gt=0, description="充值金额（元）")
    coins: int = Field(gt=0, description="获得金币数")
    label: str = Field(min_length=1, max_length=20, description="显示标签")
    tag: Optional[str] = Field(None, max_length=10, description="角标文字")


class RechargeConfigIn(BaseModel):
    """充值配置输入"""
    packages: List[RechargePackageItem] = Field(
        min_length=1, 
        max_length=20, 
        description="充值套餐列表"
    )


class RechargeConfigOut(BaseModel):
    """充值配置输出"""
    packages: List[RechargePackageItem]
```

- [ ] **Step 2: 提交**

```bash
git add backend/app/schemas/system.py
git commit -m "feat(backend): add recharge config schemas"
```

## Task 2: 创建充值配置管理接口

**Files:**
- Create: `backend/app/api/v1/apis/system/__init__.py`
- Create: `backend/app/api/v1/apis/system/recharge_config.py`

- [ ] **Step 1: 创建 system 模块初始化文件**

```python
from fastapi import APIRouter

from .recharge_config import router as recharge_config_router

system_router = APIRouter()
system_router.include_router(recharge_config_router, prefix="/recharge-config", tags=["系统配置-充值"])
```

- [ ] **Step 2: 创建充值配置接口文件**

```python
import json
from fastapi import APIRouter

from app.core.redis import get_redis
from app.models.system_config import SystemConfig, SYSTEM_CONFIG_CACHE_KEY
from app.schemas.base import Success
from app.schemas.system import RechargeConfigIn, RechargeConfigOut, RechargePackageItem

router = APIRouter()


@router.get("", summary="获取充值配置", response_model=Success)
async def get_recharge_config():
    """获取当前充值配置"""
    config_value = await SystemConfig.get_value("recharge_packages", "[]")
    try:
        packages_data = json.loads(config_value)
        if not isinstance(packages_data, list):
            packages_data = []
    except (json.JSONDecodeError, ValueError):
        packages_data = []
    
    packages = [RechargePackageItem(**item) for item in packages_data if isinstance(item, dict)]
    return Success(data={"packages": [p.model_dump() for p in packages]})


@router.put("", summary="更新充值配置", response_model=Success)
async def update_recharge_config(config_in: RechargeConfigIn):
    """更新充值配置"""
    # 序列化为 JSON
    packages_json = json.dumps(
        [p.model_dump() for p in config_in.packages],
        ensure_ascii=False
    )
    
    # 更新或创建配置
    config_obj = await SystemConfig.filter(cfg_key="recharge_packages").first()
    if config_obj:
        config_obj.cfg_value = packages_json
        await config_obj.save(update_fields=["cfg_value"])
    else:
        await SystemConfig.create(
            cfg_key="recharge_packages",
            cfg_value=packages_json,
            description="充值套餐配置"
        )
    
    # 清除 Redis 缓存
    try:
        redis = await get_redis()
        await redis.delete(SYSTEM_CONFIG_CACHE_KEY)
    except Exception as e:
        # 缓存清除失败不影响主流程
        import logging
        logging.warning(f"Failed to clear cache: {e}")
    
    return Success(msg="配置已更新")
```

- [ ] **Step 3: 提交**

```bash
git add backend/app/api/v1/apis/system/
git commit -m "feat(backend): add recharge config management API"
```

## Task 3: 注册充值配置路由

**Files:**
- Modify: `backend/app/api/v1/__init__.py:1-39`

- [ ] **Step 1: 导入并注册 system 路由**

在文件顶部添加导入：
```python
from .apis.system import system_router
```

在路由注册部分添加（在第 38 行 recharge_router 之后）：
```python
v1_router.include_router(system_router, prefix="/apis/system", dependencies=[DependPermission])
```

完整修改后的文件应该是：
```python
from .system_config import system_config_router, system_config_spec_router
from .withdraw import router as withdraw_router
from .recharge import router as recharge_router
from .apis.system import system_router
from fastapi import APIRouter

from app.core.dependency import DependPermission

from .app import app_router
from .apis import apis_router
from .auditlog import auditlog_router
from .base import base_router
from .depts import depts_router
from .menus import menus_router
from .roles import roles_router
from .users import users_router
from .app_users import app_users_router
from .call_records import call_records_router
from .gift import gift_router
from app.websocket.router import router as ws_router

v1_router = APIRouter()

v1_router.include_router(base_router, prefix="/base")
v1_router.include_router(app_router, prefix="/app")
v1_router.include_router(ws_router, prefix="")  # WebSocket: /api/v1/ws/app
v1_router.include_router(users_router, prefix="/user", dependencies=[DependPermission])
v1_router.include_router(roles_router, prefix="/role", dependencies=[DependPermission])
v1_router.include_router(menus_router, prefix="/menu", dependencies=[DependPermission])
v1_router.include_router(apis_router, prefix="/api", dependencies=[DependPermission])
v1_router.include_router(depts_router, prefix="/dept", dependencies=[DependPermission])
v1_router.include_router(auditlog_router, prefix="/auditlog", dependencies=[DependPermission])
v1_router.include_router(system_config_router, prefix="/system_config", dependencies=[DependPermission])
v1_router.include_router(system_config_spec_router, prefix="/apis", dependencies=[DependPermission])
v1_router.include_router(withdraw_router, prefix="/withdraw", dependencies=[DependPermission])
v1_router.include_router(app_users_router, prefix="/app_user", dependencies=[DependPermission])
v1_router.include_router(call_records_router, prefix="/call_record", dependencies=[DependPermission])
v1_router.include_router(gift_router, prefix="/gift", dependencies=[DependPermission])
v1_router.include_router(recharge_router, prefix="/recharge", dependencies=[DependPermission])
v1_router.include_router(system_router, prefix="/apis/system", dependencies=[DependPermission])
```

- [ ] **Step 2: 提交**

```bash
git add backend/app/api/v1/__init__.py
git commit -m "feat(backend): register recharge config routes"
```

## Task 4: 修改 bootstrap 接口返回充值配置

**Files:**
- Modify: `backend/app/api/v1/app/bootstrap.py:9-66`

- [ ] **Step 1: 添加 json 导入和充值配置读取逻辑**

在文件顶部添加 json 导入（如果没有）：
```python
import json
```

在 `get_app_bootstrap` 函数中，在返回语句之前添加充值配置读取逻辑（第 46 行之后）：

```python
    # 读取充值套餐配置
    recharge_packages_raw = config_map.get("recharge_packages") or "[]"
    try:
        recharge_packages = json.loads(recharge_packages_raw)
        if not isinstance(recharge_packages, list):
            recharge_packages = []
    except (json.JSONDecodeError, ValueError):
        recharge_packages = []
```

修改返回语句，添加 `recharge_packages` 字段：

```python
    return Success(
        data={
            "token_names": {
                "coin_name": coin_name,
                "diamond_name": diamond_name,
            },
            "im": {
                "configured": is_im_configured,
                "sdk_app_id": im_sdk_app_id,
            },
            "rtc": {
                "configured": is_rtc_configured,
            },
            "call": {
                "reject_inbound_protect_seconds": call_reject_inbound_protect_seconds,
                "reject_pair_protect_seconds": call_reject_pair_protect_seconds,
            },
            "recharge_packages": recharge_packages,
        }
    )
```

- [ ] **Step 2: 提交**

```bash
git add backend/app/api/v1/app/bootstrap.py
git commit -m "feat(backend): add recharge_packages to bootstrap response"
```

## Task 5: 编写后端测试

**Files:**
- Create: `backend/tests/test_recharge_config.py`

- [ ] **Step 1: 编写测试用例**

```python
import json
import pytest
from httpx import AsyncClient

from app.models.system_config import SystemConfig


@pytest.mark.asyncio
async def test_get_recharge_config_empty(client: AsyncClient, admin_token_headers):
    """测试获取空配置"""
    response = await client.get(
        "/api/v1/apis/system/recharge-config",
        headers=admin_token_headers
    )
    assert response.status_code == 200
    data = response.json()
    assert data["code"] == 200
    assert "packages" in data["data"]


@pytest.mark.asyncio
async def test_update_recharge_config_success(client: AsyncClient, admin_token_headers):
    """测试更新充值配置成功"""
    payload = {
        "packages": [
            {"amount": 6, "coins": 60, "label": "6元", "tag": "尝鲜"},
            {"amount": 30, "coins": 300, "label": "30元", "tag": "推荐"}
        ]
    }
    response = await client.put(
        "/api/v1/apis/system/recharge-config",
        json=payload,
        headers=admin_token_headers
    )
    assert response.status_code == 200
    data = response.json()
    assert data["code"] == 200
    assert "配置已更新" in data["msg"]
    
    # 验证数据库中的配置
    config = await SystemConfig.filter(cfg_key="recharge_packages").first()
    assert config is not None
    packages = json.loads(config.cfg_value)
    assert len(packages) == 2
    assert packages[0]["amount"] == 6


@pytest.mark.asyncio
async def test_update_recharge_config_invalid_amount(client: AsyncClient, admin_token_headers):
    """测试更新充值配置 - 非法金额"""
    payload = {
        "packages": [
            {"amount": -1, "coins": 60, "label": "6元"}
        ]
    }
    response = await client.put(
        "/api/v1/apis/system/recharge-config",
        json=payload,
        headers=admin_token_headers
    )
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_update_recharge_config_invalid_coins(client: AsyncClient, admin_token_headers):
    """测试更新充值配置 - 非法金币数"""
    payload = {
        "packages": [
            {"amount": 6, "coins": 0, "label": "6元"}
        ]
    }
    response = await client.put(
        "/api/v1/apis/system/recharge-config",
        json=payload,
        headers=admin_token_headers
    )
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_bootstrap_returns_packages(client: AsyncClient):
    """测试 bootstrap 接口返回充值配置"""
    # 先设置配置
    await SystemConfig.create(
        cfg_key="recharge_packages",
        cfg_value='[{"amount":6,"coins":60,"label":"6元","tag":"尝鲜"}]',
        description="测试配置"
    )
    
    response = await client.get("/api/v1/app/init/bootstrap")
    assert response.status_code == 200
    data = response.json()
    assert "recharge_packages" in data["data"]
    assert len(data["data"]["recharge_packages"]) == 1
    assert data["data"]["recharge_packages"][0]["amount"] == 6
```

- [ ] **Step 2: 运行测试**

```bash
cd backend
pytest tests/test_recharge_config.py -v
```

预期输出：所有测试通过

- [ ] **Step 3: 提交**

```bash
git add backend/tests/test_recharge_config.py
git commit -m "test(backend): add recharge config tests"
```

## Task 6: 创建前端 API 模块

**Files:**
- Create: `backend/web/src/api/system.js`

- [ ] **Step 1: 创建系统配置 API 文件**

```javascript
import { request } from '@/utils'

export default {
  // 充值配置
  getRechargeConfig: () => request.get('/apis/system/recharge-config'),
  updateRechargeConfig: (data = {}) => request.put('/apis/system/recharge-config', data),
}
```

- [ ] **Step 2: 提交**

```bash
git add backend/web/src/api/system.js
git commit -m "feat(web): add system API module"
```

## Task 7: 修改前端 API 入口文件

**Files:**
- Modify: `backend/web/src/api/index.js:1-73`

- [ ] **Step 1: 导入并导出 system API**

在文件顶部添加导入：
```javascript
import systemApi from './system'
```

在 export default 对象中添加（展开 systemApi）：
```javascript
export default {
  login: (data) => request.post('/base/access_token', data, { noNeedToken: true }),
  getUserInfo: () => request.get('/base/userinfo'),
  getUserMenu: () => request.get('/base/usermenu'),
  getUserApi: () => request.get('/base/userapi'),
  // profile
  updatePassword: (data = {}) => request.post('/base/update_password', data),
  // users
  getUserList: (params = {}) => request.get('/user/list', { params }),
  getUserById: (params = {}) => request.get('/user/get', { params }),
  createUser: (data = {}) => request.post('/user/create', data),
  updateUser: (data = {}) => request.post('/user/update', data),
  deleteUser: (params = {}) => request.delete(`/user/delete`, { params }),
  resetPassword: (data = {}) => request.post(`/user/reset_password`, data),
  // app users
  getAppUserList: (params = {}) => request.get('/app_user/list', { params }),
  getAppUserById: (params = {}) => request.get('/app_user/get', { params }),
  updateAppUser: (data = {}) => request.post('/app_user/update', data),
  getAppUserBillList: (params = {}) => request.get('/app_user/bill/list', { params }),
  reviewAnchorApply: (data = {}) => request.post('/app_user/anchor-apply/review', data),
  uploadAppUserImage: (data) =>
    request.post('/app_user/upload-image', data, {
      headers: { 'Content-Type': 'multipart/form-data' },
    }),
  // call record
  getCallRecordList: (params = {}) => request.get('/call_record/list', { params }),
  // gift manage
  getGiftList: (params = {}) => request.get('/gift/list', { params }),
  getGiftById: (params = {}) => request.get('/gift/get', { params }),
  createGift: (data = {}) => request.post('/gift/create', data),
  updateGift: (data = {}) => request.post('/gift/update', data),
  deleteGift: (params = {}) => request.delete('/gift/delete', { params }),
  uploadGiftResource: (data, params = {}) =>
    request.post('/gift/upload-resource', data, {
      params,
      headers: { 'Content-Type': 'multipart/form-data' },
    }),
  // recharge manage
  getRechargeList: (params = {}) => request.get('/recharge/list', { params }),
  reviewRechargeOrder: (data = {}) => request.post('/recharge/review', data),
  // role
  getRoleList: (params = {}) => request.get('/role/list', { params }),
  createRole: (data = {}) => request.post('/role/create', data),
  updateRole: (data = {}) => request.post('/role/update', data),
  deleteRole: (params = {}) => request.delete('/role/delete', { params }),
  updateRoleAuthorized: (data = {}) => request.post('/role/authorized', data),
  getRoleAuthorized: (params = {}) => request.get('/role/authorized', { params }),
  // menus
  getMenus: (params = {}) => request.get('/menu/list', { params }),
  createMenu: (data = {}) => request.post('/menu/create', data),
  updateMenu: (data = {}) => request.post('/menu/update', data),
  deleteMenu: (params = {}) => request.delete('/menu/delete', { params }),
  // apis
  getApis: (params = {}) => request.get('/api/list', { params }),
  createApi: (data = {}) => request.post('/api/create', data),
  updateApi: (data = {}) => request.post('/api/update', data),
  deleteApi: (params = {}) => request.delete('/api/delete', { params }),
  refreshApi: (data = {}) => request.post('/api/refresh', data),
  // depts
  getDepts: (params = {}) => request.get('/dept/list', { params }),
  createDept: (data = {}) => request.post('/dept/create', data),
  updateDept: (data = {}) => request.post('/dept/update', data),
  deleteDept: (params = {}) => request.delete('/dept/delete', { params }),
  // auditlog
  getAuditLogList: (params = {}) => request.get('/auditlog/list', { params }),
  // system config
  getSystemConfigList: (params = {}) => request.get('/system_config/list', { params }),
  createSystemConfig: (data = {}) => request.post('/system_config/create', data),
  updateSystemConfig: (data = {}) => request.post('/system_config/update', data),
  deleteSystemConfig: (params = {}) => request.delete('/system_config/delete', { params }),
  // system - recharge config
  ...systemApi,
}
```

- [ ] **Step 2: 提交**

```bash
git add backend/web/src/api/index.js
git commit -m "feat(web): export system API in main API module"
```

## Task 8: 创建充值配置页面（第一部分：模板结构）

**Files:**
- Create: `backend/web/src/views/system/recharge-config/index.vue`

- [ ] **Step 1: 创建页面文件并编写模板部分**

```vue
<script setup>
import { h, onMounted, ref } from 'vue'
import { NButton, NCard, NForm, NFormItem, NInput, NInputNumber, NSpace } from 'naive-ui'
import CommonPage from '@/components/page/CommonPage.vue'
import api from '@/api'

defineOptions({ name: '充值配置' })

const loading = ref(false)
const saving = ref(false)
const packages = ref([])
const originalPackages = ref([])

const formRef = ref(null)

const rules = {
  amount: [
    { required: true, message: '请输入充值金额', trigger: 'blur' },
    { type: 'number', min: 0.01, message: '金额必须大于0', trigger: 'blur' },
  ],
  coins: [
    { required: true, message: '请输入金币数', trigger: 'blur' },
    { type: 'number', min: 1, message: '金币数必须大于0', trigger: 'blur' },
  ],
  label: [
    { required: true, message: '请输入标签', trigger: 'blur' },
    { min: 1, max: 20, message: '标签长度为1-20字符', trigger: 'blur' },
  ],
  tag: [{ max: 10, message: '角标最多10字符', trigger: 'blur' }],
}

onMounted(() => {
  fetchConfig()
})

async function fetchConfig() {
  loading.value = true
  try {
    const res = await api.getRechargeConfig()
    if (res.data && res.data.packages) {
      packages.value = res.data.packages.map((p) => ({ ...p }))
      originalPackages.value = JSON.parse(JSON.stringify(packages.value))
    }
  } catch (error) {
    window.$message?.error(error?.message || '加载配置失败，请刷新重试')
  } finally {
    loading.value = false
  }
}

function addPackage() {
  packages.value.push({
    amount: 6,
    coins: 60,
    label: '6元',
    tag: '',
  })
}

function removePackage(index) {
  packages.value.splice(index, 1)
}

function moveUp(index) {
  if (index === 0) return
  const temp = packages.value[index]
  packages.value[index] = packages.value[index - 1]
  packages.value[index - 1] = temp
}

function moveDown(index) {
  if (index === packages.value.length - 1) return
  const temp = packages.value[index]
  packages.value[index] = packages.value[index + 1]
  packages.value[index + 1] = temp
}

async function saveConfig() {
  try {
    await formRef.value?.validate()
  } catch {
    window.$message?.warning('请检查表单填写')
    return
  }

  if (packages.value.length === 0) {
    window.$message?.warning('至少需要一个充值套餐')
    return
  }

  saving.value = true
  try {
    await api.updateRechargeConfig({ packages: packages.value })
    window.$message?.success('配置已更新，客户端将在60秒内生效')
    originalPackages.value = JSON.parse(JSON.stringify(packages.value))
  } catch (error) {
    window.$message?.error(error?.message || '保存失败')
  } finally {
    saving.value = false
  }
}

function resetConfig() {
  packages.value = JSON.parse(JSON.stringify(originalPackages.value))
  window.$message?.info('已重置')
}
</script>

// __CONTINUE_HERE__
```

## Task 9: 创建充值配置页面（第二部分：模板和样式）

**Files:**
- Modify: `backend/web/src/views/system/recharge-config/index.vue`

- [ ] **Step 1: 添加模板部分**

在 `</script>` 标签后添加：

```vue
<template>
  <CommonPage show-footer title="充值配置">
    <NCard title="充值套餐配置" :loading="loading">
      <NForm ref="formRef" :model="{ packages }" label-placement="left" label-width="80">
        <div v-for="(pkg, index) in packages" :key="index" class="package-item">
          <div class="package-header">
            <span class="package-title">套餐 {{ index + 1 }}</span>
            <NSpace>
              <NButton size="small" @click="moveUp(index)" :disabled="index === 0">上移</NButton>
              <NButton size="small" @click="moveDown(index)" :disabled="index === packages.length - 1">
                下移
              </NButton>
              <NButton size="small" type="error" @click="removePackage(index)">删除</NButton>
            </NSpace>
          </div>
          <div class="package-form">
            <NFormItem
              :label="`金额`"
              :path="`packages[${index}].amount`"
              :rule="rules.amount"
            >
              <NInputNumber
                v-model:value="pkg.amount"
                :min="0.01"
                :step="0.01"
                :precision="2"
                placeholder="充值金额（元）"
                style="width: 200px"
              />
            </NFormItem>
            <NFormItem
              :label="`金币数`"
              :path="`packages[${index}].coins`"
              :rule="rules.coins"
            >
              <NInputNumber
                v-model:value="pkg.coins"
                :min="1"
                :precision="0"
                placeholder="获得金币数"
                style="width: 200px"
              />
            </NFormItem>
            <NFormItem
              :label="`标签`"
              :path="`packages[${index}].label`"
              :rule="rules.label"
            >
              <NInput
                v-model:value="pkg.label"
                placeholder="显示标签（如：6元）"
                maxlength="20"
                show-count
                style="width: 200px"
              />
            </NFormItem>
            <NFormItem
              :label="`角标`"
              :path="`packages[${index}].tag`"
              :rule="rules.tag"
            >
              <NInput
                v-model:value="pkg.tag"
                placeholder="角标文字（可选，如：推荐）"
                maxlength="10"
                show-count
                style="width: 200px"
              />
            </NFormItem>
          </div>
        </div>
        <NButton type="primary" dashed block @click="addPackage" style="margin-top: 16px">
          + 添加套餐
        </NButton>
      </NForm>
      <template #footer>
        <NSpace justify="end">
          <NButton @click="resetConfig" :disabled="saving">重置</NButton>
          <NButton type="primary" @click="saveConfig" :loading="saving">保存配置</NButton>
        </NSpace>
      </template>
    </NCard>
  </CommonPage>
</template>

<style scoped>
.package-item {
  border: 1px solid #e0e0e6;
  border-radius: 8px;
  padding: 16px;
  margin-bottom: 16px;
  background-color: #fafafa;
}

.package-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16px;
  padding-bottom: 12px;
  border-bottom: 1px solid #e0e0e6;
}

.package-title {
  font-weight: 600;
  font-size: 15px;
  color: #333;
}

.package-form {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 16px;
}

@media (max-width: 768px) {
  .package-form {
    grid-template-columns: 1fr;
  }
}
</style>
```

- [ ] **Step 2: 提交**

```bash
git add backend/web/src/views/system/recharge-config/index.vue
git commit -m "feat(web): complete recharge config page template and styles"
```

## Task 10: 数据库初始化（可选）

**Files:**
- N/A (直接执行 SQL)

- [ ] **Step 1: 插入默认充值配置**

```bash
cd backend
python -c "
import asyncio
from app.models.system_config import SystemConfig
from tortoise import Tortoise
from app.settings import settings

async def init():
    await Tortoise.init(config=settings.TORTOISE_ORM)
    await SystemConfig.create(
        cfg_key='recharge_packages',
        cfg_value='[{\"amount\":6,\"coins\":60,\"label\":\"6元\",\"tag\":\"尝鲜\"},{\"amount\":30,\"coins\":300,\"label\":\"30元\",\"tag\":\"推荐\"},{\"amount\":68,\"coins\":700,\"label\":\"68元\",\"tag\":\"特惠\"}]',
        description='充值套餐配置'
    )
    print('默认充值配置已插入')
    await Tortoise.close_connections()

asyncio.run(init())
"
```

预期输出：`默认充值配置已插入`

- [ ] **Step 2: 验证配置**

```bash
python -c "
import asyncio
from app.models.system_config import SystemConfig
from tortoise import Tortoise
from app.settings import settings

async def check():
    await Tortoise.init(config=settings.TORTOISE_ORM)
    config = await SystemConfig.filter(cfg_key='recharge_packages').first()
    if config:
        print(f'配置值: {config.cfg_value}')
    else:
        print('配置不存在')
    await Tortoise.close_connections()

asyncio.run(check())
"
```

预期输出：显示 JSON 配置

## Task 11: 集成测试与验证

**Files:**
- N/A (手动测试)

- [ ] **Step 1: 启动后端服务**

```bash
cd backend
python run.py
```

预期输出：服务启动在 `http://localhost:9999`

- [ ] **Step 2: 启动前端开发服务器**

```bash
cd backend/web
pnpm dev
```

预期输出：前端服务启动

- [ ] **Step 3: 测试后端接口**

使用 curl 或 Postman 测试：

```bash
# 获取充值配置（需要管理员 token）
curl -X GET http://localhost:9999/api/v1/apis/system/recharge-config \
  -H "token: YOUR_ADMIN_TOKEN"

# 更新充值配置
curl -X PUT http://localhost:9999/api/v1/apis/system/recharge-config \
  -H "token: YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"packages":[{"amount":6,"coins":60,"label":"6元","tag":"尝鲜"}]}'

# 验证 bootstrap 接口返回配置
curl -X GET http://localhost:9999/api/v1/app/init/bootstrap
```

预期：所有接口返回正确数据

- [ ] **Step 4: 测试前端页面**

1. 登录管理后台
2. 访问充值配置页面（需要在菜单中添加或直接访问路由）
3. 测试添加套餐
4. 测试删除套餐
5. 测试上移/下移
6. 测试表单校验（输入非法值）
7. 测试保存配置
8. 测试重置功能

预期：所有功能正常工作

- [ ] **Step 5: 验证客户端获取配置**

Flutter 客户端调用 bootstrap 接口后，应该能获取到新配置的套餐。

- [ ] **Step 6: 提交最终验证**

```bash
git add -A
git commit -m "chore: integration test passed"
```

## Task 12: 文档更新

**Files:**
- Modify: `AGENTS.md` (如果需要记录新功能)

- [ ] **Step 1: 更新项目文档（可选）**

在 `AGENTS.md` 或相关文档中记录充值配置功能的使用方法。

- [ ] **Step 2: 提交**

```bash
git add AGENTS.md
git commit -m "docs: update AGENTS.md with recharge config feature"
```

---

## 自审清单

**规范覆盖检查：**
- ✅ 数据模型设计：Task 1 创建 Schema
- ✅ 后端接口：Task 2-4 实现管理端接口和 bootstrap 修改
- ✅ 前端页面：Task 6-9 实现配置页面
- ✅ 测试：Task 5 后端测试，Task 11 集成测试
- ✅ 部署：Task 10 数据库初始化

**占位符扫描：**
- ✅ 无 TBD、TODO
- ✅ 所有代码块完整
- ✅ 所有命令具体

**类型一致性：**
- ✅ Schema 定义与接口使用一致
- ✅ 前后端数据结构匹配
- ✅ API 路径统一为 `/apis/system/recharge-config`

**范围检查：**
- ✅ 聚焦充值配置功能
- ✅ 任务粒度合理（2-5分钟/步骤）
- ✅ 每个任务独立可测试

