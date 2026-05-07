from typing import List, Optional
from pydantic import BaseModel, Field, model_validator


class RechargePackageItem(BaseModel):
    """充值套餐项"""
    amount: int = Field(gt=0, le=10000000, description="充值金额（分），例如 600 表示 6.00 元")
    coins: int = Field(gt=0, description="获得金币数（分）")
    tag: Optional[str] = Field(None, max_length=10, description="角标文字")
    tag_color: Optional[str] = Field(None, max_length=20, description="角标颜色（十六进制，如 #FF5722）")


class RechargeConfigIn(BaseModel):
    """充值配置输入"""
    packages: List[RechargePackageItem] = Field(
        min_length=1,
        max_length=20,
        description="充值套餐列表"
    )


class RechargeConfigOut(BaseModel):
    """充值配置输出"""
    packages: List[RechargePackageItem]


class IMTextBillingConfigIn(BaseModel):
    """IM 文字消息计费配置输入"""
    enabled: bool = Field(default=False, description="是否开启文字聊天扣费")
    price: int = Field(default=0, ge=0, le=1000000, description="每条文字消息扣费金币数")
    anchor_share_bps: int = Field(default=5000, ge=0, le=10000, description="主播分成万分比")

    @model_validator(mode="after")
    def validate_enabled_price(self):
        if self.enabled and self.price <= 0:
            raise ValueError("price must be greater than 0 when enabled")
        return self


class IMTextBillingConfigOut(IMTextBillingConfigIn):
    """IM 文字消息计费配置输出"""
