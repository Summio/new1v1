from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `moment_media` MODIFY COLUMN `moment_id` BIGINT   COMMENT '所属动态ID';"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `moment_media` MODIFY COLUMN `moment_id` BIGINT NOT NULL  COMMENT '所属动态ID';"""
