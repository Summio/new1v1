from typing import List, Optional

from pydantic import BaseModel, Field, model_validator


class RechargePackageItem(BaseModel):
    """充值套餐项"""

    amount: int = Field(gt=0, le=10000000, description="充值金额（分），例如 600 表示 6.00 元")
    coins: int = Field(gt=0, description="获得金币数（分）")
    label: str = Field(min_length=1, max_length=20, description="套餐展示标签")
    tag: Optional[str] = Field(None, max_length=10, description="角标文字")
    tag_color: Optional[str] = Field(None, max_length=20, description="角标颜色（十六进制，如 #FF5722）")


class RechargeConfigIn(BaseModel):
    """充值配置输入"""

    packages: List[RechargePackageItem] = Field(min_length=1, max_length=20, description="充值套餐列表")


class RechargeConfigOut(BaseModel):
    """充值配置输出"""

    packages: List[RechargePackageItem]


class WithdrawPackageItem(BaseModel):
    """提现套餐项"""

    diamonds: int = Field(gt=0, description="消耗钻石数")
    amount: int = Field(gt=0, le=10000000, description="到账金额（分），例如 1000 表示 10.00 元")
    tag: Optional[str] = Field(None, max_length=10, description="角标文字")
    tag_color: Optional[str] = Field(None, max_length=20, description="角标颜色（十六进制，如 #FF5722）")


class WithdrawConfigIn(BaseModel):
    """提现配置输入"""

    packages: List[WithdrawPackageItem] = Field(
        min_length=1,
        max_length=20,
        description="提现套餐列表",
    )


class WithdrawConfigOut(BaseModel):
    """提现配置输出"""

    packages: List[WithdrawPackageItem]


class FlirtConfigIn(BaseModel):
    """搭讪配置输入"""

    filter_same_gender_enabled: bool = Field(default=True, description="过滤同性别：开启后仅展示异性用户")
    filter_certified_user_enabled: bool = Field(
        default=True,
        description="过滤认证用户：开启后隐藏真人认证用户，仅展示普通用户",
    )
    greet_daily_limit: int = Field(default=3, ge=0, le=20, description="每日打招呼次数，0 表示禁用")


class FlirtConfigOut(FlirtConfigIn):
    """搭讪配置输出"""


class IMTextBillingConfigIn(BaseModel):
    """IM 文字消息计费配置输入"""

    enabled: bool = Field(default=False, description="是否开启文字聊天扣费")
    price: int = Field(default=0, ge=0, le=1000000, description="每条文字消息扣费金币数")
    certified_user_share_bps: int = Field(default=5000, ge=0, le=10000, description="认证用户分成万分比")

    @model_validator(mode="after")
    def validate_enabled_price(self):
        if self.enabled and self.price <= 0:
            raise ValueError("price must be greater than 0 when enabled")
        return self


class IMTextBillingConfigOut(IMTextBillingConfigIn):
    """IM 文字消息计费配置输出"""


class CertifiedCallPriceConfigIn(BaseModel):
    """认证用户通话价格档位配置输入"""

    tiers: List[int] = Field(
        min_length=1,
        max_length=50,
        description="认证用户通话价格档位（金币/分钟）",
    )

    @model_validator(mode="after")
    def validate_tiers(self):
        cleaned = []
        for tier in self.tiers:
            if tier < 0:
                raise ValueError("tiers must be greater than or equal to 0")
            if tier not in cleaned:
                cleaned.append(tier)
        if not any(tier > 0 for tier in cleaned):
            raise ValueError("请至少保留一个收费档位")
        if 0 not in cleaned:
            cleaned.insert(0, 0)
        self.tiers = sorted(cleaned)
        return self
