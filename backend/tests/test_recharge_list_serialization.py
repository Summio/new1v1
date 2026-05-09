"""测试充值列表接口的 datetime 序列化"""

import json
from datetime import datetime

import pytest

from app.schemas.app_api import RechargeListItem


def test_recharge_list_item_serialization_with_datetime():
    """测试 RechargeListItem 包含 datetime 时能正确序列化为 JSON"""
    item = RechargeListItem(
        id=1,
        user_id=100,
        amount=1000,
        order_no="TEST001",
        status="paid",
        pay_channel="wx",
        created_at=datetime(2026, 5, 7, 10, 30, 0),
        paid_at=datetime(2026, 5, 7, 10, 35, 0),
        username="test_user",
    )

    # 使用 mode='json' 应该能成功序列化
    data = item.model_dump(mode="json")

    # 验证 datetime 已转换为字符串
    assert isinstance(data["created_at"], str)
    assert isinstance(data["paid_at"], str)

    # 验证能被 json.dumps 序列化
    json_str = json.dumps(data)
    assert "2026-05-07" in json_str

    # 验证反序列化后数据完整
    parsed = json.loads(json_str)
    assert parsed["id"] == 1
    assert parsed["user_id"] == 100
    assert parsed["order_no"] == "TEST001"


def test_recharge_list_item_serialization_without_mode_fails():
    """测试不使用 mode='json' 时序列化会失败（记录当前 bug）"""
    item = RechargeListItem(
        id=1,
        user_id=100,
        amount=1000,
        order_no="TEST001",
        status="paid",
        pay_channel="wx",
        created_at=datetime(2026, 5, 7, 10, 30, 0),
        paid_at=datetime(2026, 5, 7, 10, 35, 0),
        username="test_user",
    )

    # 默认 model_dump() 返回 datetime 对象
    data = item.model_dump()
    assert isinstance(data["created_at"], datetime)

    # json.dumps 应该失败
    with pytest.raises(TypeError, match="Object of type datetime is not JSON serializable"):
        json.dumps(data)


def test_recharge_list_item_with_none_datetime():
    """测试 datetime 字段为 None 时也能正确序列化"""
    item = RechargeListItem(
        id=1,
        user_id=100,
        amount=1000,
        order_no="TEST002",
        status="pending",
        pay_channel="alipay",
        created_at=datetime(2026, 5, 7, 10, 30, 0),
        paid_at=None,  # 未支付
        username="test_user",
    )

    data = item.model_dump(mode="json")

    # 验证能被序列化
    json_str = json.dumps(data)
    parsed = json.loads(json_str)

    assert parsed["created_at"] is not None
    assert parsed["paid_at"] is None
    assert parsed["status"] == "pending"
