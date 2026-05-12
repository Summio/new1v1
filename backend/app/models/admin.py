from tortoise import fields

from app.schemas.menus import MenuType

from .base import BaseModel, TimestampMixin
from .enums import MethodType


class User(BaseModel, TimestampMixin):
    username = fields.CharField(max_length=20, unique=True, description="用户名称", db_index=True)
    alias = fields.CharField(max_length=30, null=True, description="姓名", db_index=True)
    email = fields.CharField(max_length=190, unique=True, description="邮箱", db_index=True)
    phone = fields.CharField(max_length=20, null=True, description="电话", db_index=True)
    avatar = fields.CharField(max_length=500, null=True, description="头像URL")
    password = fields.CharField(max_length=128, null=True, description="密码")
    is_active = fields.BooleanField(default=True, description="是否激活", db_index=True)
    is_superuser = fields.BooleanField(default=False, description="是否为超级管理员", db_index=True)
    last_login = fields.DatetimeField(null=True, description="最后登录时间", db_index=True)
    roles = fields.ManyToManyField("models.Role", related_name="user_roles")
    dept_id = fields.IntField(null=True, description="部门ID", db_index=True)

    class Meta:
        table = "user"


class Role(BaseModel, TimestampMixin):
    name = fields.CharField(max_length=20, unique=True, description="角色名称", db_index=True)
    desc = fields.CharField(max_length=500, null=True, description="角色描述")
    menus = fields.ManyToManyField("models.Menu", related_name="role_menus")
    apis = fields.ManyToManyField("models.Api", related_name="role_apis")

    class Meta:
        table = "role"


class Api(BaseModel, TimestampMixin):
    path = fields.CharField(max_length=190, description="API路径", db_index=True)
    method = fields.CharEnumField(MethodType, description="请求方法", db_index=True)
    summary = fields.CharField(max_length=250, description="请求简介", db_index=True)
    tags = fields.CharField(max_length=250, description="API标签", db_index=True)

    class Meta:
        table = "api"


class Menu(BaseModel, TimestampMixin):
    name = fields.CharField(max_length=20, description="菜单名称", db_index=True)
    remark = fields.JSONField(null=True, description="保留字段")
    menu_type = fields.CharEnumField(MenuType, null=True, description="菜单类型")
    icon = fields.CharField(max_length=100, null=True, description="菜单图标")
    path = fields.CharField(max_length=100, description="菜单路径", db_index=True)
    order = fields.IntField(default=0, description="排序", db_index=True)
    parent_id = fields.IntField(default=0, description="父菜单ID", db_index=True)
    is_hidden = fields.BooleanField(default=False, description="是否隐藏")
    component = fields.CharField(max_length=100, description="组件")
    keepalive = fields.BooleanField(default=True, description="存活")
    redirect = fields.CharField(max_length=100, null=True, description="重定向")

    class Meta:
        table = "menu"


class Dept(BaseModel, TimestampMixin):
    name = fields.CharField(max_length=20, unique=True, description="部门名称", db_index=True)
    desc = fields.CharField(max_length=500, null=True, description="备注")
    is_deleted = fields.BooleanField(default=False, description="软删除标记", db_index=True)
    order = fields.IntField(default=0, description="排序", db_index=True)
    parent_id = fields.IntField(default=0, description="父部门ID", db_index=True)

    class Meta:
        table = "dept"


class DeptClosure(BaseModel, TimestampMixin):
    ancestor = fields.IntField(description="父代", db_index=True)
    descendant = fields.IntField(description="子代", db_index=True)
    level = fields.IntField(default=0, description="深度", db_index=True)


class AuditLog(BaseModel, TimestampMixin):
    user_id = fields.IntField(description="用户ID", db_index=True)
    username = fields.CharField(max_length=64, default="", description="用户名称", db_index=True)
    module = fields.CharField(max_length=64, default="", description="功能模块")
    summary = fields.CharField(max_length=128, default="", description="请求描述")
    method = fields.CharField(max_length=10, default="", description="请求方法")
    path = fields.CharField(max_length=255, default="", description="请求路径")
    status = fields.IntField(default=-1, description="状态码", db_index=True)
    response_time = fields.IntField(default=0, description="响应时间(单位ms)")
    request_args = fields.JSONField(null=True, description="请求参数")
    response_body = fields.JSONField(null=True, description="返回数据")


class Gift(BaseModel):
    """礼物配置"""

    name = fields.CharField(max_length=50, description="礼物名称", db_index=True)
    icon = fields.CharField(max_length=500, description="礼物图标URL")
    price = fields.BigIntField(description="价格(金币)", db_index=True)
    svga_url = fields.CharField(max_length=500, null=True, description="SVGA动画URL")
    is_active = fields.BooleanField(default=True, description="是否上架")

    class Meta:
        table = "gift"


class CallRecord(BaseModel, TimestampMixin):
    """通话记录"""

    caller_id = fields.BigIntField(description="主叫用户ID", db_index=True)
    callee_id = fields.BigIntField(description="被叫用户ID(认证用户)", db_index=True)
    call_price = fields.BigIntField(default=0, description="通话单价(金币/分钟)，以发起时价格固定计费")
    status = fields.CharField(
        max_length=20, default="pending", description="pending/ongoing/ended/failed/timeout", db_index=True
    )
    duration = fields.IntField(default=0, description="通话时长(秒)")
    total_fee = fields.BigIntField(default=0, description="总费用(金币)")
    end_reason = fields.CharField(max_length=50, null=True, description="结束原因")
    connected_at = fields.DatetimeField(null=True, description="实际接通时间")
    ended_at = fields.DatetimeField(null=True, description="结束时间")
    effective_ended_at = fields.DatetimeField(
        null=True,
        description="结算使用的实际结束时间",
    )
    end_basis = fields.CharField(
        max_length=32,
        null=True,
        description="manual_end/force_exit/timeout/balance_empty",
    )
    force_exit_user_id = fields.BigIntField(null=True, description="先离场用户ID")
    deducted_amount = fields.BigIntField(default=0, description="已扣费总额(金币)")
    deducted_minutes = fields.BigIntField(default=0, description="已扣费分钟数")
    last_renew_at = fields.DatetimeField(null=True, description="最后一次续租时间")
    billing_free_seconds = fields.BigIntField(default=10, description="本次通话免费秒数快照")
    payer_user_id = fields.BigIntField(null=True, description="本次通话付费用户ID快照")
    income_certified_user_id = fields.BigIntField(null=True, description="本次通话收益认证用户ID快照")
    certified_user_share_bps = fields.IntField(default=5000, description="本次通话认证用户分成比例快照（万分比）")
    certified_user_income_diamonds = fields.BigIntField(default=0, description="本次通话认证用户收益钻石")
    income_settled_at = fields.DatetimeField(null=True, description="认证用户收益结算时间")
    service_fee_threshold_minutes = fields.IntField(default=0, description="通话手续费阈值分钟快照")
    service_fee_rate_bps = fields.IntField(default=0, description="通话手续费比例快照(万分比)")
    service_fee_payer_rate_bps = fields.IntField(default=0, description="通话付费方手续费比例快照(万分比)")
    service_fee_income_rate_bps = fields.IntField(default=0, description="通话收益方手续费比例快照(万分比)")
    service_fee_processed_chargeable_minutes = fields.IntField(default=0, description="已处理手续费分钟数")
    service_fee_payer_expected_coins = fields.DecimalField(
        max_digits=18, decimal_places=2, default=0, description="付费方理论手续费金币"
    )
    service_fee_payer_actual_coins = fields.DecimalField(
        max_digits=18, decimal_places=2, default=0, description="付费方实扣手续费金币"
    )
    service_fee_payer_status = fields.CharField(max_length=32, null=True, description="付费方手续费状态")
    service_fee_payer_settled_at = fields.DatetimeField(null=True, description="付费方手续费结算时间")
    service_fee_income_expected_diamonds = fields.DecimalField(
        max_digits=18, decimal_places=2, default=0, description="收益方理论手续费钻石"
    )
    service_fee_income_actual_diamonds = fields.DecimalField(
        max_digits=18, decimal_places=2, default=0, description="收益方实扣手续费钻石"
    )
    service_fee_income_status = fields.CharField(max_length=32, null=True, description="收益方手续费状态")
    service_fee_income_settled_at = fields.DatetimeField(null=True, description="收益方手续费结算时间")

    class Meta:
        table = "call_record"


class GiftRecord(BaseModel, TimestampMixin):
    """礼物记录"""

    sender_id = fields.BigIntField(description="发送者ID", db_index=True)
    receiver_id = fields.BigIntField(description="接收者ID", db_index=True)
    gift_id = fields.BigIntField(description="礼物ID")
    gift_name = fields.CharField(max_length=50, description="礼物名称")
    price = fields.BigIntField(description="礼物单价(金币)")
    quantity = fields.IntField(default=1, description="礼物数量")
    total_price = fields.BigIntField(default=0, description="礼物总价(金币)")
    certified_user_share_bps = fields.IntField(default=10000, description="认证用户分成比例快照(万分比)")
    certified_user_income_diamonds = fields.DecimalField(
        max_digits=18, decimal_places=2, default=0, description="认证用户礼物收益钻石"
    )
    service_fee_threshold_coins = fields.BigIntField(default=0, description="礼物手续费阈值快照(金币)")
    service_fee_rate_bps = fields.IntField(default=0, description="礼物手续费比例快照(万分比)")
    service_fee_sender_expected_coins = fields.DecimalField(
        max_digits=18, decimal_places=2, default=0, description="送礼方理论手续费金币"
    )
    service_fee_sender_actual_coins = fields.DecimalField(
        max_digits=18, decimal_places=2, default=0, description="送礼方实扣手续费金币"
    )
    service_fee_sender_status = fields.CharField(max_length=32, null=True, description="送礼方手续费状态")
    service_fee_sender_settled_at = fields.DatetimeField(null=True, description="送礼方手续费结算时间")

    class Meta:
        table = "gift_record"


class ImTextMessageChargeRecord(BaseModel, TimestampMixin):
    """IM 文字消息扣费记录"""

    sender_id = fields.BigIntField(description="发送方用户ID", db_index=True)
    receiver_id = fields.BigIntField(description="接收方用户ID", db_index=True)
    request_id = fields.CharField(max_length=64, description="客户端请求幂等ID")
    price = fields.BigIntField(default=0, description="文字消息扣费金币数")
    certified_user_share_bps = fields.IntField(default=5000, description="认证用户分成比例快照(万分比)")
    certified_user_income_diamonds = fields.DecimalField(
        max_digits=18,
        decimal_places=2,
        default=0,
        description="认证用户收益钻石",
    )
    status = fields.CharField(max_length=20, default="charged", description="charged", db_index=True)

    class Meta:
        table = "im_text_message_charge_record"
        unique_together = (("sender_id", "request_id"),)


class RechargeOrder(BaseModel, TimestampMixin):
    """充值订单"""

    user_id = fields.BigIntField(description="用户ID", db_index=True)
    order_no = fields.CharField(max_length=64, unique=True, description="订单号", db_index=True)
    amount = fields.BigIntField(description="充值金额(分)")
    status = fields.CharField(
        max_length=20, default="pending", description="pending/paid/cancelled/refunded", db_index=True
    )
    pay_channel = fields.CharField(max_length=20, null=True, description="支付渠道: wx/alipay")
    paid_at = fields.DatetimeField(null=True, description="支付时间")

    class Meta:
        table = "recharge_order"


class WithdrawApply(BaseModel, TimestampMixin):
    """提现申请"""

    user_id = fields.BigIntField(description="用户ID", db_index=True)
    amount = fields.BigIntField(description="提现金额(分)")
    bank_name = fields.CharField(max_length=50, null=True, description="银行名称")
    account_no = fields.CharField(max_length=50, null=True, description="银行账号")
    real_name = fields.CharField(max_length=30, null=True, description="真实姓名")
    payment_qr_code = fields.CharField(max_length=500, null=True, description="收款码URL")
    status = fields.CharField(max_length=20, default="pending", description="pending/paid/rejected", db_index=True)
    processed_by = fields.BigIntField(null=True, description="处理人后台用户ID")
    review_remark = fields.CharField(max_length=500, null=True, description="处理备注/驳回原因")
    processed_at = fields.DatetimeField(null=True, description="处理时间")

    class Meta:
        table = "withdraw_apply"


class WithdrawAccount(BaseModel, TimestampMixin):
    """用户提现账户"""

    user_id = fields.BigIntField(description="用户ID", unique=True, db_index=True)
    real_name = fields.CharField(max_length=30, description="真实姓名")
    account_no = fields.CharField(max_length=80, description="支付宝账号")
    payment_qr_code = fields.CharField(max_length=500, description="收款码URL")
    status = fields.CharField(
        max_length=20,
        default="pending",
        description="审核状态: pending/approved/rejected",
        db_index=True,
    )
    reviewed_by = fields.BigIntField(null=True, description="审核人后台用户ID")
    reviewed_at = fields.DatetimeField(null=True, description="审核时间")
    review_remark = fields.CharField(max_length=500, null=True, description="审核备注/驳回原因")

    class Meta:
        table = "withdraw_account"
