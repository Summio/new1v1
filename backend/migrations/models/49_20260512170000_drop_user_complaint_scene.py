from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `user_complaint` DROP COLUMN `scene`;"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `user_complaint` ADD COLUMN `scene` VARCHAR(32) NOT NULL DEFAULT 'profile' COMMENT '投诉来源';"""
