from typing import Literal

from pydantic import BaseModel, Field, field_validator

from app.schemas.app_user import GenderType


class InitialProfileAvatarPoolIn(BaseModel):
    male: list[str] = Field(default_factory=list, description="男性头像池")
    female: list[str] = Field(default_factory=list, description="女性头像池")


class InitialProfileNicknameGroupIn(BaseModel):
    prefixes: list[str] = Field(default_factory=list, description="昵称前缀池")
    suffixes: list[str] = Field(default_factory=list, description="昵称后缀池")


class InitialProfileNicknamePoolIn(BaseModel):
    male: InitialProfileNicknameGroupIn = Field(
        default_factory=InitialProfileNicknameGroupIn,
        description="男性昵称池",
    )
    female: InitialProfileNicknameGroupIn = Field(
        default_factory=InitialProfileNicknameGroupIn,
        description="女性昵称池",
    )


class InitialProfileCompleteIn(BaseModel):
    gender: GenderType = Field(description="性别")
    avatar: str = Field(..., max_length=500, description="头像URL")
    nickname: str = Field(..., max_length=30, description="昵称")

    @field_validator("avatar", "nickname")
    @classmethod
    def _strip_value(cls, value: str) -> str:
        return value.strip()


class InitialProfileGenderIn(BaseModel):
    gender: GenderType = Field(description="性别")


class InitialProfileNicknameImportIn(BaseModel):
    gender: GenderType = Field(description="性别")
    section: Literal["prefixes", "suffixes"] = Field(description="导入类型")
    content: str = Field(default="", max_length=5000, description="多行素材内容")

    @field_validator("content")
    @classmethod
    def _strip_content(cls, value: str) -> str:
        return value.strip()


class InitialProfileUploadResult(BaseModel):
    filename: str
    url: str | None = None
    reason: str | None = None


class InitialProfileUploadOut(BaseModel):
    uploaded: list[InitialProfileUploadResult] = Field(default_factory=list)
    failed: list[InitialProfileUploadResult] = Field(default_factory=list)


class InitialProfileOptionsOut(BaseModel):
    gender: GenderType
    selected_avatar: str = ""
    selected_nickname: str = ""
