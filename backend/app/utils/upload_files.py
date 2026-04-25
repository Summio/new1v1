from pathlib import Path
from uuid import uuid4

from fastapi import UploadFile

IMAGE_MAX_BYTES = 10 * 1024 * 1024
MOMENT_IMAGE_MAX_BYTES = 1 * 1024 * 1024
VIDEO_MAX_BYTES = 8 * 1024 * 1024


class UploadValidationError(Exception):
    def __init__(self, message: str, code: int = 400):
        super().__init__(message)
        self.message = message
        self.code = code


async def read_validated_upload_file(
    file: UploadFile,
    *,
    allowed_suffixes: set[str],
    max_bytes: int,
    invalid_suffix_message: str,
    too_large_message: str,
    empty_message: str = "文件为空",
    invalid_filename_message: str = "文件名无效",
) -> tuple[str, bytes]:
    if not file.filename:
        raise UploadValidationError(invalid_filename_message)

    suffix = Path(file.filename).suffix.lower()
    if suffix not in allowed_suffixes:
        raise UploadValidationError(invalid_suffix_message)

    content = await file.read()
    if not content:
        raise UploadValidationError(empty_message)
    if len(content) > max_bytes:
        raise UploadValidationError(too_large_message)

    return suffix, content


async def read_validated_image_upload(
    file: UploadFile,
    *,
    allowed_suffixes: set[str],
    invalid_suffix_message: str = "仅支持 jpg/jpeg/png/webp",
    max_bytes: int = IMAGE_MAX_BYTES,
    too_large_message: str = "图片不能超过10MB",
) -> tuple[str, bytes]:
    return await read_validated_upload_file(
        file,
        allowed_suffixes=allowed_suffixes,
        max_bytes=max_bytes,
        invalid_suffix_message=invalid_suffix_message,
        too_large_message=too_large_message,
    )


async def read_validated_video_upload(
    file: UploadFile,
    *,
    allowed_suffixes: set[str],
    invalid_suffix_message: str,
) -> tuple[str, bytes]:
    return await read_validated_upload_file(
        file,
        allowed_suffixes=allowed_suffixes,
        max_bytes=VIDEO_MAX_BYTES,
        invalid_suffix_message=invalid_suffix_message,
        too_large_message="视频不能超过8MB",
    )


def save_upload_content(
    *,
    base_dir: str | Path,
    relative_dir: Path,
    suffix: str,
    content: bytes,
    filename: str | None = None,
) -> str:
    abs_dir = Path(base_dir) / "uploads" / relative_dir
    abs_dir.mkdir(parents=True, exist_ok=True)

    final_name = filename or f"{uuid4().hex}{suffix}"
    abs_file = abs_dir / final_name
    abs_file.write_bytes(content)

    return f"/uploads/{relative_dir.as_posix()}/{final_name}"
