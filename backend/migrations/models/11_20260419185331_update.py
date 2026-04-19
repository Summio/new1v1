from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `call_record` ADD `end_basis` VARCHAR(32)   COMMENT 'manual_end/force_exit/timeout/balance_empty';
        ALTER TABLE `call_record` ADD `force_exit_user_id` BIGINT   COMMENT '先离场用户ID';
        ALTER TABLE `call_record` ADD `effective_ended_at` DATETIME(6)   COMMENT '结算使用的实际结束时间';"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `call_record` DROP COLUMN `end_basis`;
        ALTER TABLE `call_record` DROP COLUMN `force_exit_user_id`;
        ALTER TABLE `call_record` DROP COLUMN `effective_ended_at`;"""
