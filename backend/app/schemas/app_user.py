from datetime import date, datetime
from enum import Enum
from re import compile as re_compile
from typing import List, Literal, Optional

from pydantic import BaseModel, Field, field_validator

# 中国手机号正则：支持纯数字、+86 前缀、00 前缀
_PHONE_RE = re_compile(r'^(?:(?:\+|00)86)?1[3-9]\d{9}$')
# 密码正则：至少8位，必须包含字母和数字
_PASSWORD_RE = re_compile(r'^(?=.*[A-Za-z])(?=.*\d).{8,}$')


# ===== 性别枚举 =====

class GenderType(str, Enum):
    MALE = "male"
    FEMALE = "female"
    SECRET = "secret"


# ===== 登录 =====

class AppLoginIn(BaseModel):
    phone: str = Field(..., description="手机号", example="13800138000")
    password: str = Field(..., description="密码")

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        if not _PHONE_RE.match(v):
            raise ValueError("手机号格式不正确")
        return v


class AppLoginOut(BaseModel):
    token: str
    user_id: int
    nickname: str
    avatar: Optional[str] = None
    is_anchor: bool = False


# ===== 注册 =====

class AppRegisterIn(BaseModel):
    phone: str = Field(..., description="手机号", example="13800138000")
    password: str = Field(..., min_length=8, max_length=32, description="密码(8-32位，须包含字母和数字)")
    gender: GenderType = Field(default=GenderType.SECRET, description="性别")

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        if not _PHONE_RE.match(v):
            raise ValueError("手机号格式不正确")
        return v

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        # 正则要求：至少8位，且同时包含字母和数字
        if not _PASSWORD_RE.match(v):
            raise ValueError("密码必须至少8位，且同时包含字母和数字")
        return v


class AppRegisterOut(BaseModel):
    user_id: int
    token: str


# ===== 用户信息 =====

class AppUserInfoOut(BaseModel):
    id: int
    phone: str
    nickname: Optional[str] = None
    avatar: Optional[str] = None
    gender: str = "secret"
    birth_date: Optional[date] = None
    height_cm: Optional[int] = None
    weight_kg: Optional[int] = None
    location_city: Optional[str] = None
    album_photos: List[str] = Field(default_factory=list)
    cover_url: Optional[str] = None
    coins: int = 0
    diamonds: int = 0
    frozen_diamonds: int = 0
    status: str = "normal"
    ban_reason: Optional[str] = None
    is_anchor: bool = False
    created_at: Optional[datetime] = None


class AppUserProfileUpdateIn(BaseModel):
    nickname: Optional[str] = Field(default=None, max_length=30, description="昵称")
    avatar: Optional[str] = Field(default=None, max_length=500, description="头像URL")
    gender: Optional[GenderType] = Field(default=None, description="性别")
    birth_date: Optional[date] = Field(default=None, description="出生日期")
    height_cm: Optional[int] = Field(default=None, ge=50, le=260, description="身高(cm)")
    weight_kg: Optional[int] = Field(default=None, ge=20, le=300, description="体重(kg)")
    location_city: Optional[str] = Field(default=None, max_length=50, description="所在地(省-市)")
    album_photos: Optional[List[str]] = Field(default=None, description="相册URL列表(最多6张)")
    cover_url: Optional[str] = Field(default=None, max_length=500, description="封面URL")


class AppUserAdminUpdateIn(BaseModel):
    id: int = Field(..., ge=1, description="用户ID")
    nickname: Optional[str] = Field(default=None, max_length=30, description="昵称")
    avatar: Optional[str] = Field(default=None, max_length=500, description="头像URL")
    gender: Optional[GenderType] = Field(default=None, description="性别")
    birth_date: Optional[date] = Field(default=None, description="出生日期")
    height_cm: Optional[int] = Field(default=None, ge=50, le=260, description="身高(cm)")
    weight_kg: Optional[int] = Field(default=None, ge=20, le=300, description="体重(kg)")
    location_city: Optional[str] = Field(default=None, max_length=50, description="所在地(省-市)")
    album_photos: Optional[List[str]] = Field(default=None, description="相册URL列表(最多6张)")
    cover_url: Optional[str] = Field(default=None, max_length=500, description="封面URL")
    status: Optional[Literal["normal", "banned"]] = Field(default=None, description="状态")
    is_anchor: Optional[bool] = Field(default=None, description="是否主播")
    anchor_intro: Optional[str] = Field(default=None, max_length=500, description="主播简介")
    anchor_tags: Optional[List[str]] = Field(default=None, description="主播标签")
    anchor_call_price: Optional[int] = Field(default=None, ge=10, le=1000, description="主播通话价格(分/分钟)")
    anchor_apply_status: Optional[Literal["none", "pending", "approved", "rejected"]] = Field(
        default=None,
        description="主播申请状态",
    )
    anchor_reject_reason: Optional[str] = Field(default=None, max_length=500, description="主播申请拒绝原因")
    anchor_apply_face_image: Optional[str] = Field(default=None, max_length=500, description="主播申请正面照URL")


# ===== 主播申请 =====

class AnchorApplyIn(BaseModel):
    face_photo_url: str = Field(..., max_length=500, description="正面照URL")


class AnchorApplyStatusOut(BaseModel):
    status: str  # "none" / "pending" / "approved" / "rejected"
    apply_at: Optional[datetime] = None
    reject_reason: Optional[str] = None
    face_photo_url: Optional[str] = None
    anchor_id: Optional[int] = None  # 审批通过后返回主播ID
    anchor_user_id: Optional[int] = None


class AnchorApplyReviewIn(BaseModel):
    id: int = Field(..., ge=1, description="用户ID")
    status: Literal["approved", "rejected"] = Field(..., description="审核结果")
    reject_reason: Optional[str] = Field(default=None, max_length=500, description="驳回原因")
