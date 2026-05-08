"""测试充值配置功能"""

import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.schemas.system import RechargeConfigIn, RechargePackageItem

BACKEND_ROOT = Path(__file__).resolve().parents[1]


def _read_backend_file(relative_path: str) -> str:
    """读取后端文件内容"""
    return (BACKEND_ROOT / relative_path).read_text(encoding="utf-8")


def test_recharge_package_item_validates_amount():
    """测试充值套餐金额验证"""
    # 正常金额
    item = RechargePackageItem(amount=600, coins=600, label="6元")
    assert item.amount == 600

    # 金额必须大于 0
    with pytest.raises(ValidationError) as exc_info:
        RechargePackageItem(amount=0, coins=600, label="0元")
    assert "greater than 0" in str(exc_info.value).lower()

    # 金额不能为负数
    with pytest.raises(ValidationError) as exc_info:
        RechargePackageItem(amount=-100, coins=600, label="负数")
    assert "greater than 0" in str(exc_info.value).lower()

    # 金额不能超过上限（1000万分 = 10万元）
    with pytest.raises(ValidationError) as exc_info:
        RechargePackageItem(amount=10000001, coins=10000001, label="超大金额")
    assert "less than or equal to 10000000" in str(exc_info.value).lower()


def test_recharge_package_item_validates_coins():
    """测试充值套餐金币数验证"""
    # 正常金币数
    item = RechargePackageItem(amount=600, coins=660, label="6元送60")
    assert item.coins == 660

    # 金币数必须大于 0
    with pytest.raises(ValidationError) as exc_info:
        RechargePackageItem(amount=600, coins=0, label="0金币")
    assert "greater than 0" in str(exc_info.value).lower()

    # 金币数不能为负数
    with pytest.raises(ValidationError) as exc_info:
        RechargePackageItem(amount=600, coins=-100, label="负金币")
    assert "greater than 0" in str(exc_info.value).lower()


def test_recharge_package_item_validates_label():
    """测试充值套餐标签验证"""
    # 正常标签
    item = RechargePackageItem(amount=600, coins=600, label="6元")
    assert item.label == "6元"

    # 标签不能为空
    with pytest.raises(ValidationError) as exc_info:
        RechargePackageItem(amount=600, coins=600, label="")
    assert "at least 1 character" in str(exc_info.value).lower()

    # 标签不能超过 20 字符（使用英文字符测试，因为 Pydantic 按字符数而非字节数计数）
    with pytest.raises(ValidationError) as exc_info:
        RechargePackageItem(amount=600, coins=600, label="a" * 21)
    assert "at most 20 character" in str(exc_info.value).lower()


def test_recharge_package_item_optional_tag():
    """测试充值套餐可选角标"""
    # 不带角标
    item = RechargePackageItem(amount=600, coins=600, label="6元")
    assert item.tag is None

    # 带角标
    item_with_tag = RechargePackageItem(amount=600, coins=660, label="6元", tag="热门")
    assert item_with_tag.tag == "热门"

    # 角标不能超过 10 字符（使用英文字符测试）
    with pytest.raises(ValidationError) as exc_info:
        RechargePackageItem(amount=600, coins=600, label="6元", tag="a" * 11)
    assert "at most 10 character" in str(exc_info.value).lower()


def test_recharge_config_in_validates_packages_list():
    """测试充值配置输入验证套餐列表"""
    # 正常配置
    config = RechargeConfigIn(
        packages=[
            RechargePackageItem(amount=600, coins=600, label="6元"),
            RechargePackageItem(amount=3000, coins=3300, label="30元", tag="热门"),
        ]
    )
    assert len(config.packages) == 2

    # 套餐列表不能为空
    with pytest.raises(ValidationError) as exc_info:
        RechargeConfigIn(packages=[])
    assert "at least 1 item" in str(exc_info.value).lower()

    # 套餐列表不能超过 20 个
    too_many_packages = [RechargePackageItem(amount=i * 100, coins=i * 100, label=f"{i}元") for i in range(1, 22)]
    with pytest.raises(ValidationError) as exc_info:
        RechargeConfigIn(packages=too_many_packages)
    assert "at most 20 item" in str(exc_info.value).lower()


def test_recharge_config_serialization():
    """测试充值配置序列化为 JSON"""
    config = RechargeConfigIn(
        packages=[
            RechargePackageItem(amount=600, coins=600, label="6元"),
            RechargePackageItem(amount=3000, coins=3300, label="30元", tag="热门"),
        ]
    )

    # 序列化为字典
    data = config.model_dump()
    assert len(data["packages"]) == 2
    assert data["packages"][0]["amount"] == 600
    assert data["packages"][1]["tag"] == "热门"

    # 序列化为 JSON 字符串
    json_str = json.dumps([p.model_dump() for p in config.packages], ensure_ascii=False)
    assert "6元" in json_str
    assert "热门" in json_str

    # 反序列化
    parsed = json.loads(json_str)
    assert len(parsed) == 2
    assert parsed[0]["amount"] == 600


def test_recharge_config_api_exists():
    """测试充值配置 API 路由已注册"""
    # 检查路由文件存在
    recharge_config_file = BACKEND_ROOT / "app/api/v1/apis/system/recharge_config.py"
    assert recharge_config_file.exists()

    # 检查路由已在 system router 中注册
    system_init = _read_backend_file("app/api/v1/apis/system/__init__.py")
    assert "recharge_config_router" in system_init
    assert 'prefix="/recharge-config"' in system_init

    # 检查 system router 已在 v1 router 中注册
    v1_init = _read_backend_file("app/api/v1/__init__.py")
    assert "system_router" in v1_init
    assert 'prefix="/apis/system"' in v1_init


def test_recharge_config_api_endpoints():
    """测试充值配置 API 端点定义"""
    content = _read_backend_file("app/api/v1/apis/system/recharge_config.py")

    # 检查 GET 端点
    assert "@router.get(" in content
    assert "获取充值配置" in content or "get_recharge_config" in content

    # 检查 PUT 端点
    assert "@router.put(" in content
    assert "更新充值配置" in content or "update_recharge_config" in content

    # 检查使用 SystemConfig 模型
    assert "SystemConfig" in content
    assert "recharge_packages" in content


def test_bootstrap_returns_recharge_packages():
    """测试 bootstrap 接口返回充值套餐配置"""
    content = _read_backend_file("app/api/v1/app/bootstrap.py")

    # 检查读取充值套餐配置
    assert "recharge_packages" in content
    assert "json.loads" in content

    # 检查返回数据中包含充值套餐
    assert '"recharge_packages"' in content or "'recharge_packages'" in content


def test_recharge_config_uses_system_config_model():
    """测试充值配置使用 SystemConfig 模型存储"""
    content = _read_backend_file("app/api/v1/apis/system/recharge_config.py")

    # 检查导入 SystemConfig
    assert "from app.models.system_config import SystemConfig" in content

    # 检查使用 get_value 方法
    assert "SystemConfig.get_value" in content or "get_value" in content

    # 检查使用 filter 和 save 方法
    assert "SystemConfig.filter" in content or ".filter(" in content
    assert ".save(" in content or "await config_obj.save" in content


def test_recharge_config_clears_cache_on_update():
    """测试更新充值配置时清除缓存"""
    content = _read_backend_file("app/api/v1/apis/system/recharge_config.py")

    # 检查导入 Redis 相关
    assert "get_redis" in content or "redis" in content.lower()

    # 检查清除缓存逻辑
    assert "SYSTEM_CONFIG_CACHE_KEY" in content or "delete" in content
