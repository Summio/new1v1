from pydantic import BaseModel, Field


class GiftCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=50, description="礼物名称")
    icon: str = Field(default="", max_length=500, description="礼物图标URL")
    price: int = Field(..., ge=1, le=99999999, description="礼物单价(金币)")
    svga_url: str | None = Field(default=None, max_length=500, description="SVGA 动画URL")
    is_active: bool = Field(default=True, description="是否上架")


class GiftUpdate(BaseModel):
    id: int = Field(..., ge=1, description="礼物ID")
    name: str = Field(..., min_length=1, max_length=50, description="礼物名称")
    icon: str = Field(default="", max_length=500, description="礼物图标URL")
    price: int = Field(..., ge=1, le=99999999, description="礼物单价(金币)")
    svga_url: str | None = Field(default=None, max_length=500, description="SVGA 动画URL")
    is_active: bool = Field(default=True, description="是否上架")
