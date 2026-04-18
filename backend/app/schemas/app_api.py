from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field


# ===== 主播 =====

class AnchorOut(BaseModel):
    id: int
    user_id: int
    nickname: str
    avatar: Optional[str] = None
    gender: str = "secret"
    intro: Optional[str] = None
    tags: Optional[List[str]] = None
    call_price: int = 0
    is_online: bool = False
    diamonds: int = 0


class AnchorListOut(BaseModel):
    id: int
    user_id: int
    nickname: str
    avatar: Optional[str] = None
    gender: str = "secret"
    intro: Optional[str] = None
    tags: Optional[List[str]] = None
    call_price: int = 0
    is_online: bool = False
    diamonds: int = 0


# ===== 通话 =====

class DialingIn(BaseModel):
    anchor_id: int = Field(..., description="主播ID")


class DialingOut(BaseModel):
    call_id: int
    coins: int
    can_call: bool
    callee_id: int
    callee_nickname: str
    callee_avatar: Optional[str] = None
    call_price: int = 0
    ring_timeout_seconds: int = 30
    left_seconds: int = 30
    msg: str = "余额充足"


class CallEndIn(BaseModel):
    call_id: int = Field(..., description="通话记录ID")

class CallEndOut(BaseModel):
    total_fee: int
    coins: int
    duration: int
    next_status: str = "ended"
    msg: str = "通话已结束"


class CallActionIn(BaseModel):
    call_id: int = Field(..., description="通话记录ID")


class CallActionOut(BaseModel):
    next_status: str
    msg: str


class RTCTokenIn(BaseModel):
    call_id: int = Field(..., description="通话记录ID")


class RTCTokenOut(BaseModel):
    app_id: str
    channel: str
    token: str
    uid: int
    expired_time: int
    free_seconds_before_billing: int = 10


# ===== 礼物 =====

class GiftOut(BaseModel):
    id: int
    name: str
    icon: str
    price: int


class GiftSendIn(BaseModel):
    anchor_id: int = Field(..., description="主播ID")
    gift_id: int = Field(..., description="礼物ID")


class GiftSendOut(BaseModel):
    gift_name: str
    coins: int
    msg: str = "发送成功"


# ===== 钱包 =====

class BalanceOut(BaseModel):
    coins: int
    diamonds: int
    frozen_diamonds: int = 0


class RechargeCreateIn(BaseModel):
    amount: int = Field(..., ge=6, le=100000, description="充值金额(分)，最低6分=0.06元")
    pay_channel: str = Field("wx", description="wx/alipay")


class RechargeCreateOut(BaseModel):
    order_no: str
    pay_url: Optional[str] = None
    msg: str = "订单创建成功"


class WithdrawApplyIn(BaseModel):
    amount: int = Field(..., ge=100, le=50000, description="提现金额(分)，最低1元，最高500元")
    bank_name: str = Field(..., description="银行名称")
    account_no: str = Field(..., min_length=10, max_length=23, description="银行账号(10-23位)")
    real_name: str = Field(..., description="真实姓名")


class WithdrawApplyOut(BaseModel):
    diamonds: int
    frozen_diamonds: int = 0
    msg: str = "申请已提交"


class WithdrawReviewIn(BaseModel):
    withdraw_id: int = Field(..., description="提现申请ID")
    action: str = Field(..., description="操作：approve（通过）或 reject（拒绝）")
    review_reason: Optional[str] = Field(None, description="拒绝原因")


class WithdrawListItem(BaseModel):
    id: int
    user_id: int
    amount: int
    bank_name: str
    account_no_masked: str
    real_name: str
    status: str
    created_at: Optional[datetime] = None
    processed_at: Optional[datetime] = None
    username: Optional[str] = None


# ===== Wallet Transactions =====

class TransactionRecord(BaseModel):
    id: str
    type: str  # recharge / call / gift / withdraw
    title: str
    amount: int
    is_income: bool
    created_at: str


class TransactionListOut(BaseModel):
    records: List[TransactionRecord]
    total: int
    current: int
    has_more: bool


# ===== IM =====

class IMSigOut(BaseModel):
    usersig: str
    expired_time: int
    sdk_app_id: int
