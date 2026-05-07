from pathlib import Path


TARGET_FILES = [
    Path("app/api/v1/app/gift.py"),
    Path("app/api/v1/app/wallet.py"),
    Path("app/api/v1/withdraw/withdraw.py"),
    Path("app/services/im_text_billing_service.py"),
]


def test_non_call_modules_do_not_use_model_class_fields_for_atomic_update() -> None:
    forbidden = ("AppUser.coins", "AppUser.diamonds")
    for rel_path in TARGET_FILES:
        content = rel_path.read_text(encoding="utf-8")
        for token in forbidden:
            assert token not in content, f"{rel_path} contains forbidden token: {token}"
