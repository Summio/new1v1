from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field, model_validator

# ===== 认证用户 =====


class CertifiedUserOut(BaseModel):
    id: int
    user_id: int
    nickname: str
    avatar: Optional[str] = None
    gender: str = "male"
    intro: Optional[str] = None
    tags: Optional[List[str]] = None
    call_price: int = 0
    is_online: bool = False
    diamonds: int = 0


class CertifiedUserListOut(BaseModel):
    id: int
    user_id: int
    nickname: str
    avatar: Optional[str] = None
    gender: str = "male"
    intro: Optional[str] = None
    tags: Optional[List[str]] = None
    call_price: int = 0
    is_online: bool = False
    diamonds: int = 0


# ===== 通话 =====


class DialingIn(BaseModel):
    target_user_id: Optional[int] = Field(default=None, description="目标用户ID(app_user.id)")
    target_id: Optional[int] = Field(default=None, description="兼容字段: 目标用户ID")

    @model_validator(mode="after")
    def validate_target_user_id(self):
        if self.target_user_id is None and self.target_id is None:
            raise ValueError("target_user_id is required")
        if self.target_user_id is None:
            self.target_user_id = self.target_id
        return self


class DialingOut(BaseModel):
    call_id: int
    coins: float
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
    total_fee: float
    coins: float
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
    svga_url: Optional[str] = None


class GiftSendIn(BaseModel):
    target_user_id: Optional[int] = Field(default=None, description="目标用户ID(app_user.id)")
    target_id: Optional[int] = Field(default=None, description="兼容字段: 目标用户ID")
    gift_id: int = Field(..., description="礼物ID")
    quantity: int = Field(default=1, ge=1, le=1, description="赠送数量，仅支持单次1件")
    scene: str = Field(default="chat", description="送礼场景: chat/call")
    call_id: Optional[int] = Field(default=None, ge=1, description="通话ID(scene=call时可传)")
    request_id: Optional[str] = Field(default=None, min_length=8, max_length=64, description="客户端请求幂等ID")

    @model_validator(mode="after")
    def validate_target_user_id(self):
        if self.target_user_id is None and self.target_id is None:
            raise ValueError("target_user_id is required")
        if self.target_user_id is None:
            self.target_user_id = self.target_id
        scene = (self.scene or "").strip()
        if scene not in {"chat", "call"}:
            raise ValueError("scene must be chat or call")
        self.scene = scene
        return self


class GiftSendOut(BaseModel):
    gift_id: int
    gift_name: str
    gift_icon: Optional[str] = None
    svga_url: Optional[str] = None
    quantity: int = 1
    unit_price: int = 0
    total_price: int = 0
    certified_user_income_diamonds: float = 0.0
    coins: float
    msg: str = "发送成功"


# ===== 钱包 =====


class BalanceOut(BaseModel):
    coins: float
    diamonds: float
    frozen_diamonds: float = 0.0
    coin_name: str = "金币"
    diamond_name: str = "钻石"


class RechargeCreateIn(BaseModel):
    amount: int = Field(..., ge=6, le=100000, description="充值金额(分)，最低6分=0.06元")
    pay_channel: str = Field("wx", description="wx/alipay")


class RechargeCreateOut(BaseModel):
    order_no: str
    pay_url: Optional[str] = None
    msg: str = "订单创建成功"


class RechargeReviewIn(BaseModel):
    order_id: int = Field(..., description="充值订单ID")
    action: str = Field(..., description="操作：mark_paid（标记已支付）")


class RechargeListItem(BaseModel):
    id: int
    user_id: int
    amount: int
    order_no: str
    status: str
    pay_channel: str
    created_at: Optional[datetime] = None
    paid_at: Optional[datetime] = None
    username: Optional[str] = None


class WithdrawApplyIn(BaseModel):
    amount: int = Field(..., ge=100, le=50000, description="提现金额(分)，最低1元，最高500元")
    bank_name: str = Field(default="支付宝", description="提现渠道")
    account_no: str = Field(default="", min_length=1, max_length=80, description="支付宝账号")
    real_name: str = Field(default="", min_length=1, max_length=30, description="真实姓名")
    payment_qr_code: str = Field(default="", max_length=500, description="收款码URL")


class WithdrawApplyOut(BaseModel):
    diamonds: float
    frozen_diamonds: float = 0.0
    msg: str = "申请已提交"


class WithdrawAccountIn(BaseModel):
    real_name: str = Field(..., min_length=1, max_length=30, description="真实姓名")
    account_no: str = Field(..., min_length=1, max_length=80, description="支付宝账号")
    payment_qr_code: str = Field(..., min_length=1, max_length=500, description="收款码URL")


class WithdrawAccountOut(BaseModel):
    real_name: str = ""
    account_no: str = ""
    payment_qr_code: str = ""
    has_account: bool = False
    status: str = ""
    review_remark: str = ""
    reviewed_at: Optional[datetime] = None
    can_withdraw: bool = False


class WithdrawAccountReviewIn(BaseModel):
    account_id: int = Field(..., description="提现账户ID")
    action: str = Field(..., description="操作：approve（通过）或 reject（驳回）")
    review_remark: Optional[str] = Field(None, max_length=500, description="审核备注/驳回原因")
    review_reason: Optional[str] = Field(None, max_length=500, description="兼容旧字段：驳回原因")


class WithdrawAccountListItem(BaseModel):
    id: int
    user_id: int
    real_name: str
    account_no: str = ""
    account_no_masked: str = ""
    payment_qr_code: str = ""
    status: str
    review_remark: str = ""
    reviewed_by: Optional[int] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    reviewed_at: Optional[datetime] = None
    username: Optional[str] = None


class WithdrawReviewIn(BaseModel):
    withdraw_id: int = Field(..., description="提现申请ID")
    action: str = Field(..., description="操作：approve（确认已打款）或 reject（拒绝）")
    review_remark: Optional[str] = Field(None, max_length=500, description="处理备注/驳回原因")
    review_reason: Optional[str] = Field(None, max_length=500, description="兼容旧字段：拒绝原因")


class WithdrawListItem(BaseModel):
    id: int
    user_id: int
    amount: int
    bank_name: str
    account_no: str = ""
    account_no_masked: str
    real_name: str
    payment_qr_code: str = ""
    status: str
    review_remark: str = ""
    processed_by: Optional[int] = None
    created_at: Optional[datetime] = None
    processed_at: Optional[datetime] = None
    username: Optional[str] = None


# ===== Wallet Transactions =====


class TransactionRecord(BaseModel):
    id: str
    type: str  # recharge / call / gift / withdraw
    title: str
    amount: float
    is_income: bool
    created_at: str
    counterparty_name: str = ""
    status: str = ""


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


class IMTextChargeIn(BaseModel):
    receiver_user_id: int = Field(..., gt=0, description="接收方 App 用户 ID")
    request_id: str = Field(..., min_length=8, max_length=64, description="客户端请求幂等 ID")


class IMTextChargeOut(BaseModel):
    charged: bool = False
    price: int = 0
    certified_user_income_diamonds: float = 0.0
    coins: int = 0
    diamonds: int = 0
    receiver_user_id: int
    request_id: str


class FlirtGreetIn(BaseModel):
    slot_index: int = Field(..., ge=1, le=3, description="常用语槽位")


class FlirtGreetQuotaOut(BaseModel):
    daily_limit: int = 3
    used: int = 0
    remaining: int = 0
    enabled: bool = True
    cooldown_seconds: int = 0


# ===== 勿扰设置 =====


class DndSettingsIn(BaseModel):
    text_dnd_enabled: bool = False
    video_dnd_enabled: bool = False
    ranking_invisible_enabled: bool = False


class DndSettingsOut(DndSettingsIn):
    pass
