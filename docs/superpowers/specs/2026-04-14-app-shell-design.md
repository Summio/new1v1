# 补充页面、注册流程、主播角色切换设计文档

**日期**: 2026-04-14
**项目**: 欢喜 (Huanxi) 1v1 视频交友 App

---

## 一、背景与目标

本次开发包含以下功能：

1. **登录/注册改造** — 去掉验证码，统一为手机号+密码方式
2. **补充页面** — 用户协议、隐私政策、密码修改页面
3. **主播/用户角色切换** — 根据 `is_anchor` 自动识别，主播显示额外功能
4. **Token Bug 修复** — 延长过期时间，优化 401 后的跳转体验

---

## 二、详细设计

### 2.1 登录/注册改造

#### 2.1.1 后端改动

| 接口 | 改动 |
|------|------|
| `POST /app/login` | 去掉 `code` 参数，只支持 `phone` + `password` |
| `POST /app/register` | 去掉 `code` 参数，只支持 `phone` + `password` + `confirm_password` |

**代码位置**: `backend/app/api/v1/app/register.py`

#### 2.1.2 前端改动

**登录页** (`lib/modules/auth/login_page.dart`):
- 去掉「使用验证码登录」切换按钮
- 保留手机号 + 密码输入
- 密码明文/密文切换保留

**注册页** (新建 `lib/modules/auth/register_page.dart`):
- 字段：手机号、密码、确认密码
- 校验：手机号格式、密码长度、两次密码一致
- 提交：调用 `POST /app/register`

**路由** (`lib/app/routes/app_router.dart`):
- 新增 `/register` 路由
- 登录页底部添加「没有账号？去注册」链接

---

### 2.2 补充页面

#### 2.2.1 后端新接口

| 接口 | 方法 | 说明 |
|------|------|------|
| `/app/agreement` | GET | 返回用户协议文本（Markdown） |
| `/app/privacy` | GET | 返回隐私政策文本（Markdown） |
| `/app/change_password` | POST | 修改密码，参数：`old_password`, `new_password` |

**实现要点**:
- 协议/政策接口需要 `DependAppAuth` 认证
- 修改密码需要校验旧密码正确

#### 2.2.2 前端页面

| 页面 | 文件 | 说明 |
|------|------|------|
| 用户协议 | `lib/modules/settings/agreement_page.dart` | 调用 `/app/agreement`，用 `flutter_markdown` 渲染 |
| 隐私政策 | `lib/modules/settings/privacy_page.dart` | 调用 `/app/privacy`，用 `flutter_markdown` 渲染 |
| 密码修改 | `lib/modules/settings/change_password_page.dart` | 表单：旧密码、新密码、确认密码 |

**路由**:
```
/settings/agreement   # 用户协议
/settings/privacy    # 隐私政策
/settings/password  # 密码修改
```

**设置页改造**:
- 「用户协议」点击跳转 `/settings/agreement`
- 「隐私政策」点击跳转 `/settings/privacy`
- 「账号与安全」点击跳转 `/settings/password`

---

### 2.3 主播/用户角色切换

#### 2.3.1 数据流

登录时后端返回 `is_anchor` 字段，前端存储为 `appRole`（当前已有）。

#### 2.3.2 前端实现

**「我的」页面** (`lib/modules/home/profile_page.dart`):

| 角色 | 额外显示 |
|------|----------|
| 普通用户 | 无额外 |
| 主播 (`appRole == 'anchor'`) | - 主播认证标识<br>- 在线接单开关<br>- 累计收益<br>- 提现入口 |

**具体 UI**:
1. 头像下方显示「认证主播」徽章（仅主播）
2. 功能列表新增「在线接单」Switch（仅主播，存本地 `is_online`）
3. 功能列表新增「累计收益 ¥XXX」（仅主播，从用户信息获取）
4. 功能列表新增「提现」入口（仅主播）

---

### 2.4 Token Bug 修复

#### 2.4.1 问题描述

- Token 过期后进入首页，401 错误直接显示在页面上
- 没有跳转到登录页，体验极差

#### 2.4.2 解决方案

**后端** (`backend/app/settings/config.py`):
```python
# JWT 过期时间从 7 天改为 30 天
JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 30
```

**前端** — 全局 401 处理:

方案：在 `app_router.dart` 的 redirect 中检查 token 有效性，或在 `api_interceptor.dart` 捕获 401 后触发跳转。

推荐方案：`api_interceptor.dart` 的 `onResponse` 已经有 401 处理，返回 `UnauthorizedException`。需要在调用层统一 catch 并跳转。

具体实现：
1. `api_interceptor.dart` 的 401 处理中，调用 `StorageService.clearUserData()`（已有）
2. 在 `app_router.dart` 的 redirect 中，检测 token 是否存在但可能无效（可以通过尝试调用 `/app/user/info` 来验证）
3. 或者在每个页面的错误处理中，如果是 401，统一跳转到登录页

**最简单的修复**:
在 `app_router.dart` 的 redirect 中，调用 `/app/user/info` 验证 token 有效性，如果 401 则清除存储并跳转到登录页：

```dart
redirect: (context, state) async {
  final token = StorageService.getToken();
  if (token != null && token.isNotEmpty) {
    // 验证 token
    try {
      await DioClient.instance.apiGet('app/user/info');
    } catch (e) {
      // token 无效，清除并跳转登录
      await StorageService.clearUserData();
      return AppRoutes.login;
    }
  }
  // ... 原有逻辑
}
```

---

## 三、验收标准

1. **登录/注册**: 手机号+密码登录成功；注册页可创建新账号
2. **补充页面**: 协议页、政策页、密码修改页可正常访问
3. **主播切换**: 主播账号登录后可见额外功能（在线开关、收益、提现）
4. **Token Bug**: Token 30 天不过期；401 后自动跳转到登录页

---

## 四、技术依赖

- 前端需添加 `flutter_markdown` 依赖
- 后端需新增 3 个接口
- 后端需修改 2 个现有接口