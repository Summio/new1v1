"""
初始化 FaceBeauty Key 到数据库
用法: python -m scripts.init_face_beauty_key
"""
import asyncio
import sys
from pathlib import Path

# 添加 backend 目录到 path
sys.path.insert(0, str(Path(__file__).parent.parent))

from tortoise import Tortoise
from app.models.system_config import SystemConfig


async def main():
    KEY = "face_beauty_key"
    VALUE = "123456"
    DESC = "FaceBeauty 美颜 SDK 授权 Key"

    # 注意：此处的数据库连接信息需与 backend/.env 中的配置保持一致
    await Tortoise.init(
        db_url="mysql://root:123456@localhost:3306/huanxi",
        modules={"models": ["app.models"]},
    )
    await Tortoise.generate_schemas()

    existing = await SystemConfig.filter(cfg_key=KEY).first()
    if existing:
        print(f"[INFO] 配置 '{KEY}' 已存在，值为: {existing.cfg_value}")
        existing.cfg_value = VALUE
        existing.description = DESC
        await existing.save()
        print(f"[OK] 已更新为: {VALUE}")
    else:
        await SystemConfig.create(
            cfg_key=KEY,
            cfg_value=VALUE,
            description=DESC,
        )
        print(f"[OK] 已创建: {KEY} = {VALUE}")

    await Tortoise.close_connections()


if __name__ == "__main__":
    asyncio.run(main())
