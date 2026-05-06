from typing import List, Optional
from pydantic import BaseModel, Field


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
