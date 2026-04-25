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

VIDEO_MAX_BYTES = _UPLOAD_FILES.VIDEO_MAX_BYTES
UploadValidationError = _UPLOAD_FILES.UploadValidationError
read_validated_video_upload = _UPLOAD_FILES.read_validated_video_upload


@pytest.mark.asyncio
async def test_read_validated_video_upload_rejects_oversized_video() -> None:
    upload = UploadFile(
        file=BytesIO(b"a" * (VIDEO_MAX_BYTES + 1)),
        filename="too-large.mp4",
    )

    with pytest.raises(UploadValidationError) as exc:
        await read_validated_video_upload(
            upload,
            allowed_suffixes={".mp4", ".mov"},
            invalid_suffix_message="仅支持 mp4/mov",
        )

    assert exc.value.message == "视频不能超过8MB"


@pytest.mark.asyncio
async def test_read_validated_video_upload_rejects_invalid_suffix() -> None:
    upload = UploadFile(file=BytesIO(b"avi-bytes"), filename="bad.avi")

    with pytest.raises(UploadValidationError) as exc:
        await read_validated_video_upload(
            upload,
            allowed_suffixes={".mp4", ".mov"},
            invalid_suffix_message="仅支持 mp4/mov",
        )

    assert exc.value.message == "仅支持 mp4/mov"
