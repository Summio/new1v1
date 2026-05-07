from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `withdraw_apply` ADD `processed_by` BIGINT COMMENT '处理人后台用户ID';
        ALTER TABLE `withdraw_apply` ADD `review_remark` VARCHAR(500) COMMENT '处理备注/驳回原因';"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `withdraw_apply` DROP COLUMN `review_remark`;
        ALTER TABLE `withdraw_apply` DROP COLUMN `processed_by`;"""
