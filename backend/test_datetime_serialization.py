"""验证 datetime 序列化问题和解决方案"""
import json
from datetime import datetime
from typing import Optional

from pydantic import BaseModel


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


def test_model_dump_default():
    """测试默认 model_dump() - 应该失败"""
    item = RechargeListItem(
        id=1,
        user_id=100,
        amount=1000,
        order_no="TEST001",
        status="paid",
        pay_channel="wx",
        created_at=datetime.now(),
        paid_at=datetime.now(),
        username="测试用户",
    )

    data = item.model_dump()
    print("[OK] model_dump() returned type:", type(data["created_at"]))

    try:
        json.dumps(data)
        print("[FAIL] Unexpected: json.dumps() succeeded")
    except TypeError as e:
        print(f"[OK] Expected error: {e}")


def test_model_dump_json_mode():
    """测试 model_dump(mode='json') - 应该成功"""
    item = RechargeListItem(
        id=1,
        user_id=100,
        amount=1000,
        order_no="TEST001",
        status="paid",
        pay_channel="wx",
        created_at=datetime.now(),
        paid_at=datetime.now(),
        username="测试用户",
    )

    data = item.model_dump(mode="json")
    print("\n[OK] model_dump(mode='json') returned type:", type(data["created_at"]))

    try:
        result = json.dumps(data)
        print("[OK] json.dumps() succeeded")
        print("[OK] Serialized result sample:", result[:100] + "...")
    except TypeError as e:
        print(f"[FAIL] Unexpected error: {e}")


if __name__ == "__main__":
    print("=== Test 1: Default model_dump() ===")
    test_model_dump_default()

    print("\n=== Test 2: model_dump(mode='json') ===")
    test_model_dump_json_mode()
