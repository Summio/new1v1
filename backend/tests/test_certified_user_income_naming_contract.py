from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

FORBIDDEN_INCOME_TOKENS = (
    "income_anchor_user_id",
    "anchor_share_bps",
    "anchor_income_diamonds",
    "call_anchor_share_bps",
    "gift_anchor_share_bps",
    "im_text_message_anchor_share_bps",
    "calc_anchor_income",
    "calc_gift_anchor_income",
    "calc_im_text_anchor_income",
    "get_anchor_share_bps",
    "get_gift_anchor_share_bps",
    "settle_call_anchor_income_once",
    "resolve_income_anchor_id",
    "incomeAnchorUserId",
    "anchorIncomeDiamonds",
)

SCAN_PATHS = (
    "backend/app",
    "backend/web/src",
    "huanxi/lib",
)


def _source_files() -> list[Path]:
    files: list[Path] = []
    for relative_path in SCAN_PATHS:
        base = ROOT / relative_path
        files.extend(
            path
            for path in base.rglob("*")
            if path.suffix in {".py", ".vue", ".js", ".ts", ".dart"}
        )
    return files


def test_income_business_code_uses_certified_user_naming() -> None:
    offenders: list[str] = []
    for path in _source_files():
        content = path.read_text(encoding="utf-8")
        for token in FORBIDDEN_INCOME_TOKENS:
            if token in content:
                offenders.append(f"{path.relative_to(ROOT)} contains {token}")

    assert offenders == []


def test_tests_do_not_use_legacy_anchor_as_current_domain_name() -> None:
    offenders: list[str] = []
    tests_dir = ROOT / "backend/tests"

    for path in sorted(tests_dir.glob("test_*.py")):
        if "anchor" in path.name.lower():
            offenders.append(f"{path.relative_to(ROOT)} uses anchor in filename")

        for line in path.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if not stripped.startswith("def test_"):
                continue
            test_name = stripped.split("(", 1)[0].removeprefix("def ")
            lowered = test_name.lower()
            if "anchor" in lowered and "legacy" not in lowered:
                offenders.append(f"{path.relative_to(ROOT)}::{test_name}")

    assert offenders == []


def test_income_migration_renames_legacy_anchor_columns() -> None:
    migration = (
        ROOT / "backend/migrations/models/39_20260509100000_certified_user_income_fields.py"
    ).read_text(encoding="utf-8")

    assert "`income_anchor_user_id` `income_certified_user_id`" in migration
    assert "`anchor_share_bps` `certified_user_share_bps`" in migration
    assert "`anchor_income_diamonds` `certified_user_income_diamonds`" in migration
    assert "call_anchor_share_bps" in migration
    assert "call_certified_user_share_bps" in migration
    assert "gift_anchor_share_bps" in migration
    assert "gift_certified_user_share_bps" in migration
    assert "im_text_message_anchor_share_bps" in migration
    assert "im_text_message_certified_user_share_bps" in migration


