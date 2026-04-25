# Backend 图片上传 1MB 限制 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为后端所有前端图片上传接口统一增加单图 1MB 限制，并抽取公共图片上传校验/保存函数复用，保持现有返回结构和视频上传限制不变。

**Architecture:** 新增一个后端上传工具模块，封装图片文件名校验、后缀校验、1MB 大小限制和保存到 `/uploads/...` 的公共逻辑。`app/user/upload-image`、`app/moment/upload` 中的图片与封面、`app_user/upload-image` 全部改为复用该工具；`moment/upload` 的视频主文件仍保持原视频大小限制与原逻辑。

**Tech Stack:** FastAPI + pathlib + pytest

---

### Task 1: 为统一图片上传工具写失败测试

**Files:**
- Create: `backend/tests/test_upload_image_helpers.py`

- [ ] **Step 1: 写失败测试**

```python
def test_validate_image_upload_rejects_oversized_image(): ...
def test_save_upload_content_returns_uploads_relative_url(tmp_path): ...
```

- [ ] **Step 2: 运行测试确认失败**

Run: `pytest -vv -s backend/tests/test_upload_image_helpers.py`
Expected: FAIL，提示上传工具模块不存在。

### Task 2: 实现统一图片上传校验/保存工具

**Files:**
- Create: `backend/app/utils/upload_files.py`

- [ ] **Step 1: 实现统一图片上传异常、1MB 限制常量、图片读取校验函数**

```python
IMAGE_MAX_BYTES = 1 * 1024 * 1024

async def read_validated_image_upload(...): ...
```

- [ ] **Step 2: 实现统一保存函数，返回 `/uploads/...` 相对 URL**

```python
def save_upload_content(...)-> str: ...
```

- [ ] **Step 3: 运行测试确认通过**

Run: `pytest -vv -s backend/tests/test_upload_image_helpers.py`
Expected: PASS

### Task 3: 接入三个前端图片上传接口

**Files:**
- Modify: `backend/app/api/v1/app/user.py`
- Modify: `backend/app/api/v1/app/moment.py`
- Modify: `backend/app/api/v1/app_users/app_users.py`

- [ ] **Step 1: `app/user/upload-image` 改为复用公共图片上传工具**
- [ ] **Step 2: `app_user/upload-image` 改为复用公共图片上传工具**
- [ ] **Step 3: `app/moment/upload` 中图片与封面复用公共图片上传工具，视频主文件保留原 100MB 限制**

### Task 4: 验证改造结果

**Files:**
- Test: `backend/tests/test_upload_image_helpers.py`

- [ ] **Step 1: 运行新增测试**

Run: `pytest -vv -s backend/tests/test_upload_image_helpers.py`
Expected: PASS

- [ ] **Step 2: 运行后端静态检查**

Run: `python -m pytest -vv -s backend/tests/test_upload_image_helpers.py`
Expected: PASS
