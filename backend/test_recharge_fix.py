"""集成测试：验证充值列表接口的序列化修复"""

import sys
from datetime import datetime
from pathlib import Path

# 添加项目根目录到 Python 路径
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.schemas.app_api import RechargeListItem
from app.schemas.base import SuccessExtra


def test_recharge_list_response_serialization():
    """模拟 recharge_list 接口的响应序列化"""
    print("=== 测试充值列表响应序列化 ===\n")

    # 模拟数据库查询结果
    items = [
        RechargeListItem(
            id=1,
            user_id=100,
            amount=1000,
            order_no="TEST001",
            status="paid",
            pay_channel="wx",
            created_at=datetime(2026, 5, 7, 10, 30, 0),
            paid_at=datetime(2026, 5, 7, 10, 35, 0),
            username="user_100",
        ),
        RechargeListItem(
            id=2,
            user_id=101,
            amount=2000,
            order_no="TEST002",
            status="pending",
            pay_channel="alipay",
            created_at=datetime(2026, 5, 7, 11, 0, 0),
            paid_at=None,
            username="user_101",
        ),
    ]

    total = 2
    page = 1
    page_size = 10

    # 模拟接口返回（修复后的代码）
    try:
        response = SuccessExtra(
            data=[item.model_dump(mode="json") for item in items],
            total=total,
            page=page,
            page_size=page_size,
        )
        print("[OK] SuccessExtra 响应创建成功")
        print(f"[OK] 响应状态码: {response.status_code}")
        print(f"[OK] 响应体类型: {type(response.body)}")
        print(f"[OK] 响应体前 200 字符: {response.body[:200].decode('utf-8')}...")
    except Exception as e:
        print(f"[FAIL] 响应创建失败: {e}")
        import traceback

        traceback.print_exc()
        raise


def test_old_code_would_fail():
    """验证旧代码（不使用 mode='json'）会失败"""
    print("\n=== 验证旧代码会失败 ===\n")

    items = [
        RechargeListItem(
            id=1,
            user_id=100,
            amount=1000,
            order_no="TEST001",
            status="paid",
            pay_channel="wx",
            created_at=datetime(2026, 5, 7, 10, 30, 0),
            paid_at=datetime(2026, 5, 7, 10, 35, 0),
            username="user_100",
        ),
    ]

    try:
        # 旧代码：不使用 mode='json'
        SuccessExtra(
            data=[item.model_dump() for item in items],
            total=1,
            page=1,
            page_size=10,
        )
        print("[FAIL] 旧代码意外成功了（不应该发生）")
        raise AssertionError("旧代码意外成功了（不应该发生）")
    except TypeError as e:
        if "datetime" in str(e) and "JSON serializable" in str(e):
            print(f"[OK] 旧代码按预期失败: {e}")
        else:
            print(f"[FAIL] 旧代码失败但错误不符合预期: {e}")
            raise


if __name__ == "__main__":
    success1 = test_recharge_list_response_serialization()
    success2 = test_old_code_would_fail()

    print("\n=== 测试总结 ===")
    if success1 and success2:
        print("[OK] 所有测试通过！修复有效。")
        sys.exit(0)
    else:
        print("[FAIL] 部分测试失败")
        sys.exit(1)
