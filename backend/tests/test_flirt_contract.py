import asyncio
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.api.v1.app import flirt
from app.schemas.system import FlirtConfigIn

REPO_ROOT = Path(__file__).resolve().parents[2]
BACKEND_ROOT = REPO_ROOT / "backend"

FLIRT_API = BACKEND_ROOT / "app/api/v1/app/flirt.py"
FLIRT_CONFIG_API = BACKEND_ROOT / "app/api/v1/apis/system/flirt_config.py"
SYSTEM_INIT = BACKEND_ROOT / "app/api/v1/apis/system/__init__.py"
APP_INIT = BACKEND_ROOT / "app/api/v1/app/__init__.py"
WEB_SYSTEM_API = BACKEND_ROOT / "web/src/api/system.js"
WEB_FLIRT_CONFIG_VIEW = BACKEND_ROOT / "web/src/views/system/flirt-config/index.vue"
INIT_APP = BACKEND_ROOT / "app/core/init_app.py"


def test_flirt_config_schema_defaults_enable_both_filters() -> None:
    config = FlirtConfigIn()

    assert config.filter_same_gender_enabled is True
    assert config.filter_certified_user_enabled is True
    assert config.greet_daily_limit == 3
    assert config.greet_cooldown_seconds == 10


def test_flirt_config_greet_daily_limit_range() -> None:
    assert FlirtConfigIn(greet_daily_limit=0).greet_daily_limit == 0
    assert FlirtConfigIn(greet_daily_limit=20).greet_daily_limit == 20

    with pytest.raises(ValidationError):
        FlirtConfigIn(greet_daily_limit=-1)
    with pytest.raises(ValidationError):
        FlirtConfigIn(greet_daily_limit=21)


def test_flirt_config_greet_cooldown_seconds_range() -> None:
    assert FlirtConfigIn(greet_cooldown_seconds=0).greet_cooldown_seconds == 0
    assert FlirtConfigIn(greet_cooldown_seconds=3600).greet_cooldown_seconds == 3600

    with pytest.raises(ValidationError):
        FlirtConfigIn(greet_cooldown_seconds=-1)
    with pytest.raises(ValidationError):
        FlirtConfigIn(greet_cooldown_seconds=3601)


def test_flirt_config_admin_api_is_registered_and_clears_cache() -> None:
    assert FLIRT_CONFIG_API.exists()
    api_text = FLIRT_CONFIG_API.read_text(encoding="utf-8")
    system_init = SYSTEM_INIT.read_text(encoding="utf-8")

    assert "flirt_filter_same_gender_enabled" in api_text
    assert "flirt_filter_certified_user_enabled" in api_text
    assert "flirt_greet_daily_limit" in api_text
    assert "flirt_greet_cooldown_seconds" in api_text
    assert "filter_same_gender_enabled" in api_text
    assert "filter_certified_user_enabled" in api_text
    assert "greet_daily_limit" in api_text
    assert "greet_cooldown_seconds" in api_text
    assert "SYSTEM_CONFIG_CACHE_KEY" in api_text
    assert "get_redis" in api_text
    assert "flirt_config_router" in system_init
    assert 'prefix="/flirt-config"' in system_init


def test_app_flirt_list_api_contract_and_registration() -> None:
    assert FLIRT_API.exists()
    api_text = FLIRT_API.read_text(encoding="utf-8")
    app_init = APP_INIT.read_text(encoding="utf-8")

    assert '@router.get("/flirt/list"' in api_text
    assert "is_certified_user" in api_text
    assert "return Fail(code=403" in api_text
    assert "exclude_blocked_user_ids" in api_text
    assert "filter_same_gender_enabled" in api_text
    assert "filter_certified_user_enabled" in api_text
    assert "coins" in api_text
    assert "availability_status" in api_text
    assert "availability_label" in api_text
    assert "build_availability_payload_map" in api_text
    assert "flirt_router" in app_init
    assert "app_router.include_router(flirt_router" in app_init


def test_app_flirt_greet_api_contract() -> None:
    assert FLIRT_API.exists()
    api_text = FLIRT_API.read_text(encoding="utf-8")

    assert '@router.get("/flirt/greet/quota"' in api_text
    assert '@router.post("/flirt/greet"' in api_text
    assert "FlirtGreetIn" in api_text
    assert "AppUserCommonPhrase" in api_text
    assert "approved_content" in api_text
    assert "text_dnd_enabled" in api_text
    assert "BackgroundTasks" in api_text
    assert "_run_flirt_greet_send_task" in api_text
    assert "background_tasks.add_task" in api_text
    assert '"started": True' in api_text
    assert "reserve_greet_quota" in api_text
    assert "set_greet_cooldown" in api_text
    assert "cooldown_seconds=int(config.greet_cooldown_seconds)" in api_text
    assert "release_greet_quota" in api_text
    assert "ensure_interaction_allowed" in api_text
    assert "InteractionRelationError" in api_text
    assert 'action="im_text"' in api_text
    assert "get_online_user_ids" in api_text
    assert "Success(data=" in api_text
    route_body = api_text.split('@router.post("/flirt/greet"', 1)[1]
    route_body = route_body.split("async def _run_flirt_greet_send_task", 1)[0]
    assert "await send_text_message" not in route_body
    assert "sendable_target_user_ids" in route_body
    assert "interaction_limit_failed_count" in route_body
    assert "if not sendable_target_user_ids" in route_body
    assert "await release_greet_quota" in route_body


def test_flirt_greet_has_target_cap_and_bounded_background_concurrency() -> None:
    api_text = FLIRT_API.read_text(encoding="utf-8")
    task_body = api_text.split("async def _run_flirt_greet_send_task", 1)[1]

    assert "FLIRT_GREET_TARGET_LIMIT = 100" in api_text
    assert "FLIRT_GREET_SEND_CONCURRENCY = 10" in api_text
    assert "limit=FLIRT_GREET_TARGET_LIMIT" in api_text
    assert ".limit(limit)" in api_text
    assert "asyncio.Semaphore(FLIRT_GREET_SEND_CONCURRENCY)" in task_body
    assert "asyncio.create_task" in task_body
    assert "interaction_limit_failed_count" in task_body


@pytest.mark.asyncio
async def test_flirt_greet_background_send_limits_concurrency(monkeypatch: pytest.MonkeyPatch) -> None:
    active = 0
    max_active = 0
    sent_to: list[int] = []

    async def fake_send_text_message(sender_id: int, receiver_id: int, text: str, **kwargs) -> bool:
        nonlocal active, max_active
        active += 1
        max_active = max(max_active, active)
        await asyncio.sleep(0.01)
        sent_to.append(receiver_id)
        active -= 1
        return True

    monkeypatch.setattr(flirt, "send_text_message", fake_send_text_message)

    await flirt._run_flirt_greet_send_task(
        sender_id=100001,
        target_user_ids=list(range(1, 26)),
        text_dnd_user_ids=[101],
        interaction_limit_failed_user_ids=[102],
        content="你好",
    )

    assert sorted(sent_to) == list(range(1, 26))
    assert max_active == flirt.FLIRT_GREET_SEND_CONCURRENCY


@pytest.mark.asyncio
async def test_flirt_greet_background_send_isolates_single_im_exception(monkeypatch: pytest.MonkeyPatch) -> None:
    sent_to: list[int] = []

    async def fake_send_text_message(sender_id: int, receiver_id: int, text: str, **kwargs) -> bool:
        if receiver_id == 3:
            raise RuntimeError("tim down")
        sent_to.append(receiver_id)
        return True

    monkeypatch.setattr(flirt, "send_text_message", fake_send_text_message)

    await flirt._run_flirt_greet_send_task(
        sender_id=100001,
        target_user_ids=[1, 2, 3, 4, 5],
        text_dnd_user_ids=[],
        interaction_limit_failed_user_ids=[],
        content="你好",
    )

    assert sorted(sent_to) == [1, 2, 4, 5]


def test_flirt_list_uses_bounded_candidate_scan_not_full_table_sort() -> None:
    api_text = FLIRT_API.read_text(encoding="utf-8")

    assert '.order_by("-coins", "-id")' in api_text
    assert "limit(candidate_batch_size)" in api_text
    assert "offset(scan_offset)" in api_text
    assert "AppUser.all()" not in api_text
    assert "await q.all()" not in api_text


def test_flirt_list_sorts_by_availability_rank_then_coins_then_id() -> None:
    api_text = FLIRT_API.read_text(encoding="utf-8")

    assert "FLIRT_AVAILABILITY_RANK" in api_text
    assert '"online": 3' in api_text
    assert '"busy": 3' in api_text
    assert '"dnd": 2' in api_text
    assert '"offline": 1' in api_text
    assert "decimal_to_float_2(user.coins)" in api_text
    assert "rank" in api_text
    assert "coins_value" in api_text


def test_admin_flirt_config_page_and_menu_exist() -> None:
    assert WEB_FLIRT_CONFIG_VIEW.exists()
    view_text = WEB_FLIRT_CONFIG_VIEW.read_text(encoding="utf-8")
    web_api_text = WEB_SYSTEM_API.read_text(encoding="utf-8")
    init_app_text = INIT_APP.read_text(encoding="utf-8")

    assert "搭讪配置" in view_text
    assert "过滤同性别" in view_text
    assert "开启后仅展示异性用户" in view_text
    assert "过滤认证用户" in view_text
    assert "开启后隐藏真人认证用户，仅展示普通用户" in view_text
    assert "每日打招呼次数" in view_text
    assert "打招呼冷却时间" in view_text
    assert "两次打招呼之间的间隔秒数，0 表示不冷却，默认 10 秒" in view_text
    assert "NInputNumber" in view_text
    assert "greet_daily_limit" in view_text
    assert "greet_cooldown_seconds" in view_text
    assert "getFlirtConfig" in web_api_text
    assert "updateFlirtConfig" in web_api_text
    assert "/apis/system/flirt-config" in web_api_text
    assert 'name="搭讪配置"' in init_app_text
    assert 'path="flirt-config"' in init_app_text
    assert 'component="/system/flirt-config"' in init_app_text
