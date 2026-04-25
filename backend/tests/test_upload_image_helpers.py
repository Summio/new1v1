import importlib.util
from io import BytesIO
from pathlib import Path

import pytest
from fastapi import UploadFile

_MODULE_PATH = Path(__file__).resolve().parents[1] / "app" / "utils" / "upload_files.py"
_SPEC = importlib.util.spec_from_file_location("upload_files", _MODULE_PATH)
assert _SPEC is not None and _SPEC.loader is not None
_UPLOAD_FILES = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_UPLOAD_FILES)

IMAGE_MAX_BYTES = _UPLOAD_FILES.IMAGE_MAX_BYTES
MOMENT_IMAGE_MAX_BYTES = _UPLOAD_FILES.MOMENT_IMAGE_MAX_BYTES
UploadValidationError = _UPLOAD_FILES.UploadValidationError
read_validated_image_upload = _UPLOAD_FILES.read_validated_image_upload
save_upload_content = _UPLOAD_FILES.save_upload_content


@pytest.mark.asyncio
async def test_read_validated_image_upload_rejects_image_over_default_limit() -> None:
    upload = UploadFile(
        file=BytesIO(b"a" * (IMAGE_MAX_BYTES + 1)),
        filename="too-large.jpg",
    )

    with pytest.raises(UploadValidationError) as exc:
        await read_validated_image_upload(
            upload,
            allowed_suffixes={".jpg", ".jpeg", ".png", ".webp"},
        )

    assert exc.value.message == "图片不能超过10MB"


@pytest.mark.asyncio
async def test_read_validated_image_upload_supports_stricter_custom_limit() -> None:
    upload = UploadFile(
        file=BytesIO(b"a" * (MOMENT_IMAGE_MAX_BYTES + 1)),
        filename="too-large.jpg",
    )

    with pytest.raises(UploadValidationError) as exc:
        await read_validated_image_upload(
            upload,
            allowed_suffixes={".jpg", ".jpeg", ".png", ".webp"},
            max_bytes=MOMENT_IMAGE_MAX_BYTES,
            too_large_message="图片不能超过1MB",
        )

    assert exc.value.message == "图片不能超过1MB"


@pytest.mark.asyncio
async def test_read_validated_image_upload_supports_custom_suffixes() -> None:
    upload = UploadFile(file=BytesIO(b"gif-bytes"), filename="animated.gif")

    suffix, content = await read_validated_image_upload(
        upload,
        allowed_suffixes={".jpg", ".jpeg", ".png", ".webp", ".gif"},
        invalid_suffix_message="仅支持 jpg/jpeg/png/gif/webp",
    )

    assert suffix == ".gif"
    assert content == b"gif-bytes"


def test_save_upload_content_returns_uploads_relative_url(tmp_path: Path) -> None:
    relative_url = save_upload_content(
        base_dir=tmp_path,
        relative_dir=Path("profile") / "123",
        suffix=".jpg",
        content=b"avatar-bytes",
        filename="fixed-name.jpg",
    )

    assert relative_url == "/uploads/profile/123/fixed-name.jpg"
    assert (tmp_path / "uploads" / "profile" / "123" / "fixed-name.jpg").read_bytes() == b"avatar-bytes"
