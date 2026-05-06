from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `system_config` MODIFY COLUMN `cfg_value` LONGTEXT NOT NULL  COMMENT '配置值';"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `system_config` MODIFY COLUMN `cfg_value` VARCHAR(255) NOT NULL  COMMENT '配置值';"""
