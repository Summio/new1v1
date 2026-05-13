from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]


def _read_backend_file(relative_path: str) -> str:
    return (BACKEND_ROOT / relative_path).read_text(encoding="utf-8")


def test_app_user_balance_adjust_contract() -> None:
    api_src = _read_backend_file("app/api/v1/app_users/app_users.py")
    schema_src = _read_backend_file("app/schemas/app_user.py")
    web_api_src = _read_backend_file("web/src/api/index.js")
    web_view_src = _read_backend_file("web/src/views/operation/app-user/index.vue")

    assert '@router.post("/balance/adjust"' in api_src
    assert "AppUserBalanceAdjustIn" in api_src
    assert 'coins=F("coins") + req_in.amount' in api_src
    assert 'diamonds=F("diamonds") + req_in.amount' in api_src
    assert "select_for_update()" in api_src
    assert "before_amount < amount" in api_src
    assert "AppUserTokenAdjustRecord.create" in api_src

    assert "class AppUserBalanceAdjustIn" in schema_src
    assert 'asset_type: Literal["coins", "diamonds"]' in schema_src
    assert 'action: Literal["increase", "decrease"]' in schema_src
    assert 'amount: int = Field(..., gt=0' in schema_src
    assert 'reason: str = Field(..., min_length=1, max_length=500' in schema_src

    assert "adjustAppUserBalance" in web_api_src
    assert "balance/adjust" in web_api_src

    assert "balanceAdjustModal" in web_view_src
    assert "handleAdjustBalance" in web_view_src
    assert "handleSubmitBalanceAdjust" in web_view_src
    assert "金币" in web_view_src
    assert "钻石" in web_view_src
    assert "增加" in web_view_src
    assert "扣除" in web_view_src
    assert "请填写操作原因" in web_view_src
