from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user` ADD `signature` VARCHAR(500) COMMENT '个性签名';"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user` DROP COLUMN `signature`;"""
