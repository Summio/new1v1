# 个人主页关注与动态头像跳转实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 去掉个人主页里重复的“离线”状态文案，增加可用的关注/取消关注能力，并让发现页动态卡片头像可进入同一个用户主页。

**Architecture:** 复用现有 `AnchorDetailPage` 作为用户主页入口，但把它从“只能接收列表页传入的完整对象”改成“可按 `userId` 自行加载详情”。后端新增最小关注关系表和 App 侧关注接口，页面通过一个关注状态接口决定按钮文案，点击后调用关注/取消关注接口并刷新当前状态。动态页头像只负责跳转到用户主页，不在卡片内引入额外业务逻辑。

**Tech Stack:** FastAPI, Tortoise ORM, Aerich migrations, Pydantic, Flutter, Riverpod, Dio, go_router.

---

## File Map

- Modify `backend/app/models/*.py`: 新增关注关系模型并导出。
- Modify `backend/app/api/v1/app/user.py`: 增加用户主页详情、关注状态、关注/取消关注接口。
- Modify `backend/app/schemas/app_user.py` 或相邻 App schema 文件：增加关注相关输入输出 schema。
- Modify `backend/migrations/models/*.py`: 新增一份 Aerich 迁移，创建关注表。
- Modify `huanxi/lib/modules/home/anchor_detail_page.dart`: 支持按 `userId` 加载个人主页，去掉重复“离线”，增加关注按钮。
- Modify `huanxi/lib/modules/home/moment_card.dart`: 头像点击跳转到用户主页。
- Modify `huanxi/lib/app/routes/app_router.dart`: 给用户主页补一个可按 `userId` 进入的路由参数。
- Modify `huanxi/lib/core/constants/api_endpoints.dart` 和 `huanxi/lib/services/*`：补关注相关 API。
- Test `backend/tests/*` 和 Flutter 的现有测试/分析命令：验证接口和页面编译通过。

## Assumptions

- 关注关系先做“用户-用户”双向可查询的最小实现，不额外做粉丝列表页、关注数展示或推荐算法联动。
- 个人主页仍使用现有主播详情视觉风格；若目标用户不是主播，页面允许展示基本资料并隐藏不适用操作。
- 动态头像点击只负责进入主页，不额外处理评论、点赞或消息入口。

---

### Task 1: 后端关注关系与主页数据接口

**Files:**
- Modify: `backend/app/models/*.py`
- Modify: `backend/app/api/v1/app/user.py`
- Modify: `backend/app/schemas/app_user.py`
- Modify: `backend/migrations/models/<new_migration>.py`
- Test: `backend/tests/test_user_follow.py`

- [ ] **Step 1: 先写接口契约测试**

```python
def test_follow_flow_contract():
    assert "GET /user/public" in user_module
    assert "GET /user/follow/status" in user_module
    assert "POST /user/follow" in user_module
    assert "DELETE /user/follow" in user_module
```

- [ ] **Step 2: 跑测试确认失败**

Run:

```bash
cd backend
pytest -q tests/test_user_follow.py
```

Expected: 由于模型/接口尚不存在而失败。

- [ ] **Step 3: 最小实现关注模型、接口和迁移**

```python
class UserFollow(BaseModel, TimestampMixin):
    follower_id = fields.IntField(index=True)
    following_id = fields.IntField(index=True)

    class Meta:
        table = "user_follow"
        unique_together = ("follower_id", "following_id")
```

```python
@router.get("/user/public")
async def get_user_public_profile(user_id: int = Query(...)):
    ...

@router.get("/user/follow/status")
async def get_follow_status(user_id: int = Query(...)):
    ...

@router.post("/user/follow")
async def follow_user(req_in: UserFollowIn):
    ...

@router.delete("/user/follow")
async def unfollow_user(user_id: int = Query(...)):
    ...
```

- [ ] **Step 4: 跑测试确认通过**

Run:

```bash
cd backend
pytest -q tests/test_user_follow.py
```

Expected: 通过。

- [ ] **Step 5: 提交这一段改动**

```bash
git add backend/app/models backend/app/api/v1/app/user.py backend/app/schemas/app_user.py backend/migrations/models backend/tests/test_user_follow.py
git commit -m "feat: add user follow endpoints"
```

### Task 2: Flutter 个人主页与动态头像跳转

**Files:**
- Modify: `huanxi/lib/app/routes/app_router.dart`
- Modify: `huanxi/lib/modules/home/anchor_detail_page.dart`
- Modify: `huanxi/lib/modules/home/moment_card.dart`
- Modify: `huanxi/lib/core/constants/api_endpoints.dart`
- Modify: `huanxi/lib/services/*`（如果需要补关注 API）

- [ ] **Step 1: 先写页面跳转/按钮行为测试或最小可验证代码**

```dart
final result = await context.push(
  AppRoutes.userHome,
  extra: {'userId': moment.userId},
);
```

- [ ] **Step 2: 跑 `flutter analyze` 看当前代码是否还编译**

Run:

```bash
cd huanxi
flutter analyze
```

Expected: 在未实现新路由/页面状态前会报缺失引用或类型不匹配。

- [ ] **Step 3: 实现页面按 userId 加载、去重状态文案、关注按钮**

```dart
if (anchor.isOnline != null) ...[
  // 顶部状态保留
]
// 删除下面重复的“离线”信息 chip
```

```dart
ElevatedButton(
  onPressed: _toggleFollow,
  child: Text(_isFollowing ? '已关注' : '关注'),
)
```

```dart
GestureDetector(
  onTap: () => context.push(AppRoutes.userHome, extra: {'userId': moment.userId}),
  child: _UserAvatar(...),
)
```

- [ ] **Step 4: 跑 `flutter analyze` 通过**

Run:

```bash
cd huanxi
flutter analyze
```

Expected: 无新增分析错误。

- [ ] **Step 5: 提交这一段改动**

```bash
git add huanxi/lib/app/routes/app_router.dart huanxi/lib/modules/home/anchor_detail_page.dart huanxi/lib/modules/home/moment_card.dart huanxi/lib/core/constants/api_endpoints.dart
git commit -m "feat: open user home from moment avatars"
```

### Task 3: 端到端验证

**Files:**
- No new code; run checks only.

- [ ] **Step 1: 验证后端测试**

Run:

```bash
cd backend
pytest -q tests/test_user_follow.py
```

- [ ] **Step 2: 验证 Flutter 静态检查**

Run:

```bash
cd huanxi
flutter analyze
```

- [ ] **Step 3: 手工核对交互**

检查三处：

```text
1. 个人主页顶部只保留一个在线/离线状态
2. 关注按钮可切换文案和状态
3. 动态卡片头像点击可进入对应用户主页
```
