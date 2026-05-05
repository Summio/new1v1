from tortoise import fields

from app.schemas.menus import MenuType

from .base import BaseModel, TimestampMixin
from .enums import MethodType


class User(BaseModel, TimestampMixin):
    username = fields.CharField(max_length=20, unique=True, description="用户名称", index=True)
    alias = fields.CharField(max_length=30, null=True, description="姓名", index=True)
    email = fields.CharField(max_length=190, unique=True, description="邮箱", index=True)
    phone = fields.CharField(max_length=20, null=True, description="电话", index=True)
    password = fields.CharField(max_length=128, null=True, description="密码")
    is_active = fields.BooleanField(default=True, description="是否激活", index=True)
    is_superuser = fields.BooleanField(default=False, description="是否为超级管理员", index=True)
    last_login = fields.DatetimeField(null=True, description="最后登录时间", index=True)
    roles = fields.ManyToManyField("models.Role", related_name="user_roles")
    dept_id = fields.IntField(null=True, description="部门ID", index=True)

    class Meta:
        table = "user"


class Role(BaseModel, TimestampMixin):
    name = fields.CharField(max_length=20, unique=True, description="角色名称", index=True)
    desc = fields.CharField(max_length=500, null=True, description="角色描述")
    menus = fields.ManyToManyField("models.Menu", related_name="role_menus")
    apis = fields.ManyToManyField("models.Api", related_name="role_apis")

    class Meta:
        table = "role"


class Api(BaseModel, TimestampMixin):
    path = fields.CharField(max_length=190, description="API路径", index=True)
    method = fields.CharEnumField(MethodType, description="请求方法", index=True)
    summary = fields.CharField(max_length=250, description="请求简介", index=True)
    tags = fields.CharField(max_length=250, description="API标签", index=True)

    class Meta:
        table = "api"


class Menu(BaseModel, TimestampMixin):
    name = fields.CharField(max_length=20, description="菜单名称", index=True)
    remark = fields.JSONField(null=True, description="保留字段")
    menu_type = fields.CharEnumField(MenuType, null=True, description="菜单类型")
    icon = fields.CharField(max_length=100, null=True, description="菜单图标")
    path = fields.CharField(max_length=100, description="菜单路径", index=True)
    order = fields.IntField(default=0, description="排序", index=True)
    parent_id = fields.IntField(default=0, description="父菜单ID", index=True)
    is_hidden = fields.BooleanField(default=False, description="是否隐藏")
    component = fields.CharField(max_length=100, description="组件")
    keepalive = fields.BooleanField(default=True, description="存活")
    redirect = fields.CharField(max_length=100, null=True, description="重定向")

    class Meta:
        table = "menu"


class Dept(BaseModel, TimestampMixin):
    name = fields.CharField(max_length=20, unique=True, description="部门名称", index=True)
    desc = fields.CharField(max_length=500, null=True, description="备注")
    is_deleted = fields.BooleanField(default=False, description="软删除标记", index=True)
    order = fields.IntField(default=0, description="排序", index=True)
    parent_id = fields.IntField(default=0, description="父部门ID", index=True)

    class Meta:
        table = "dept"


class DeptClosure(BaseModel, TimestampMixin):
    ancestor = fields.IntField(description="父代", index=True)
    descendant = fields.IntField(description="子代", index=True)
    level = fields.IntField(default=0, description="深度", index=True)


class AuditLog(BaseModel, TimestampMixin):
    user_id = fields.IntField(description="用户ID", index=True)
    username = fields.CharField(max_length=64, default="", description="用户名称", index=True)
    module = fields.CharField(max_length=64, default="", description="功能模块")
    summary = fields.CharField(max_length=128, default="", description="请求描述")
    method = fields.CharField(max_length=10, default="", description="请求方法")
    path = fields.CharField(max_length=255, default="", description="请求路径")
    status = fields.IntField(default=-1, description="状态码", index=True)
    response_time = fields.IntField(default=0, description="响应时间(单位ms)")
    request_args = fields.JSONField(null=True, description="请求参数")
    response_body = fields.JSONField(null=True, description="返回数据")


class Gift(BaseModel):
    """礼物配置"""
    name = fields.CharField(max_length=50, description="礼物名称", index=True)
    icon = fields.CharField(max_length=500, description="礼物图标URL")
    price = fields.BigIntField(description="价格(分)", index=True)
    svga_url = fields.CharField(max_length=500, null=True, description="SVGA动画URL")
    is_active = fields.BooleanField(default=True, description="是否上架")

    class Meta:
        table = "gift"


class CallRecord(BaseModel, TimestampMixin):
    """通话记录"""
    caller_id = fields.BigIntField(description="主叫用户ID", index=True)
    callee_id = fields.BigIntField(description="被叫用户ID(主播)", index=True)
    call_price = fields.BigIntField(default=0, description="通话单价(分/分钟)，以发起时价格固定计费")
    status = fields.CharField(max_length=20, default="pending", description="pending/ongoing/ended/failed/timeout", index=True)
    duration = fields.IntField(default=0, description="通话时长(秒)")
    total_fee = fields.BigIntField(default=0, description="总费用(分)")
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
    deducted_amount = fields.BigIntField(default=0, description="已扣费总额(分)")
    deducted_minutes = fields.BigIntField(default=0, description="已扣费分钟数")
    last_renew_at = fields.DatetimeField(null=True, description="最后一次续租时间")
    billing_free_seconds = fields.BigIntField(default=10, description="本次通话免费秒数快照")
    payer_user_id = fields.BigIntField(null=True, description="本次通话付费用户ID快照")
    income_anchor_user_id = fields.BigIntField(null=True, description="本次通话收益主播ID快照")
    anchor_share_bps = fields.IntField(default=5000, description="本次通话主播分成比例快照（万分比）")
    anchor_income_diamonds = fields.BigIntField(default=0, description="本次通话主播收益钻石(分)")
    income_settled_at = fields.DatetimeField(null=True, description="主播收益结算时间")

    class Meta:
        table = "call_record"


class GiftRecord(BaseModel, TimestampMixin):
    """礼物记录"""
    sender_id = fields.BigIntField(description="发送者ID", index=True)
    receiver_id = fields.BigIntField(description="接收者ID", index=True)
    gift_id = fields.BigIntField(description="礼物ID")
    gift_name = fields.CharField(max_length=50, description="礼物名称")
    price = fields.BigIntField(description="礼物单价(分)")
    quantity = fields.IntField(default=1, description="礼物数量")
    total_price = fields.BigIntField(default=0, description="礼物总价(分)")
    anchor_share_bps = fields.IntField(default=10000, description="主播分成比例快照(万分比)")
    anchor_income_diamonds = fields.BigIntField(default=0, description="主播礼物收益钻石(分)")

    class Meta:
        table = "gift_record"


class RechargeOrder(BaseModel, TimestampMixin):
    """充值订单"""
    user_id = fields.BigIntField(description="用户ID", index=True)
    order_no = fields.CharField(max_length=64, unique=True, description="订单号", index=True)
    amount = fields.BigIntField(description="充值金额(分)")
    status = fields.CharField(max_length=20, default="pending", description="pending/paid/cancelled/refunded", index=True)
    pay_channel = fields.CharField(max_length=20, null=True, description="支付渠道: wx/alipay")
    paid_at = fields.DatetimeField(null=True, description="支付时间")

    class Meta:
        table = "recharge_order"


class WithdrawApply(BaseModel, TimestampMixin):
    """提现申请"""
    user_id = fields.BigIntField(description="用户ID", index=True)
    amount = fields.BigIntField(description="提现金额(分)")
    bank_name = fields.CharField(max_length=50, null=True, description="银行名称")
    account_no = fields.CharField(max_length=50, null=True, description="银行账号")
    real_name = fields.CharField(max_length=30, null=True, description="真实姓名")
    status = fields.CharField(max_length=20, default="pending", description="pending/processed/rejected", index=True)
    processed_at = fields.DatetimeField(null=True, description="处理时间")

    class Meta:
        table = "withdraw_apply"
