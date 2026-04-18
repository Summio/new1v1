from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `call_record` ADD `billing_free_seconds` BIGINT NOT NULL  COMMENT '本次通话免费秒数快照' DEFAULT 10;
        ALTER TABLE `call_record` ADD `payer_user_id` BIGINT   COMMENT '本次通话付费用户ID快照';"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `call_record` DROP COLUMN `billing_free_seconds`;
        ALTER TABLE `call_record` DROP COLUMN `payer_user_id`;"""
