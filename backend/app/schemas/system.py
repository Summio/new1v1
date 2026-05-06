from typing import List, Optional
from pydantic import BaseModel, Field


class RechargePackageItem(BaseModel):
    """充值套餐项"""
    amount: float = Field(gt=0, description="充值金额（元）")
    coins: int = Field(gt=0, description="获得金币数")
    label: str = Field(min_length=1, max_length=20, description="显示标签")
    tag: Optional[str] = Field(None, max_length=10, description="角标文字")


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
