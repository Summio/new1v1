from datetime import datetime
from enum import Enum
from re import compile as re_compile
from typing import Optional

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
    coins: int = 0
    diamonds: int = 0
    frozen_diamonds: int = 0
    status: str = "normal"
    ban_reason: Optional[str] = None
    is_anchor: bool = False
    created_at: Optional[datetime] = None


# ===== 主播申请 =====

class AnchorApplyIn(BaseModel):
    intro: str = Field(..., max_length=500, description="申请简介")
    tags: Optional[list] = Field(default_factory=list, description="擅长领域标签")
    call_price: int = Field(default=60, ge=10, le=1000, description="期望通话价格(分/分钟)")


class AnchorApplyStatusOut(BaseModel):
    status: str  # "none" / "pending" / "approved" / "rejected"
    apply_at: Optional[datetime] = None
    reject_reason: Optional[str] = None
    anchor_id: Optional[int] = None  # 审批通过后返回主播ID
