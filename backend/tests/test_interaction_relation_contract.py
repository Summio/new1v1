from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]


def _read_backend_file(relative_path: str) -> str:
    return (BACKEND_ROOT / relative_path).read_text(encoding="utf-8")


def test_interaction_entrypoints_use_shared_guard() -> None:
    follow_src = _read_backend_file("app/api/v1/app/user.py")
    im_src = _read_backend_file("app/api/v1/app/im.py")
    call_src = _read_backend_file("app/api/v1/app/call.py")
    gift_src = _read_backend_file("app/api/v1/app/gift.py")

    assert "ensure_interaction_allowed" in follow_src
    assert 'action="follow"' in follow_src
    assert "ensure_interaction_allowed" in im_src
    assert 'action="im_text"' in im_src
    assert "ensure_interaction_allowed" in call_src
    assert 'action="call"' in call_src
    assert "ensure_interaction_allowed" in gift_src
    assert 'action="gift"' in gift_src


def test_interaction_service_uses_system_config_and_customer_service_bypass() -> None:
    service_src = _read_backend_file("app/services/interaction_relation_service.py")

    assert "SystemConfig.get_all_as_dict" in service_src
    assert "load_customer_service_config" in service_src
    assert "interaction_follow_opposite_gender_enabled" in service_src
    assert "interaction_im_text_certified_mix_enabled" in service_src
    assert "interaction_call_opposite_gender_enabled" in service_src
    assert "interaction_gift_certified_mix_enabled" in service_src


def test_admin_system_config_page_exposes_interaction_limits() -> None:
    page_src = _read_backend_file("web/src/views/system/config/index.vue")

    assert "互动限制" in page_src
    for key in [
        "interaction_follow_opposite_gender_enabled",
        "interaction_follow_certified_mix_enabled",
        "interaction_im_text_opposite_gender_enabled",
        "interaction_im_text_certified_mix_enabled",
        "interaction_call_opposite_gender_enabled",
        "interaction_call_certified_mix_enabled",
        "interaction_gift_opposite_gender_enabled",
        "interaction_gift_certified_mix_enabled",
    ]:
        assert key in page_src
