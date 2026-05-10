from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `moments` ADD `review_status` VARCHAR(20) NOT NULL DEFAULT 'approved' COMMENT '审核状态 pending/approved/rejected';
        ALTER TABLE `moments` ADD `reviewed_at` DATETIME(6) NULL COMMENT '审核时间';
        ALTER TABLE `moments` ADD `reviewed_by` BIGINT NULL COMMENT '审核后台用户ID';
        ALTER TABLE `moments` ADD `review_remark` VARCHAR(500) NULL COMMENT '审核备注';
        UPDATE `moments` SET `review_status` = 'approved' WHERE `review_status` IS NULL OR `review_status` = '';
        CREATE INDEX `idx_moments_review_status` ON `moments` (`review_status`);
        CREATE INDEX `idx_moments_user_review_status` ON `moments` (`user_id`, `review_status`);
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DROP INDEX `idx_moments_user_review_status` ON `moments`;
        DROP INDEX `idx_moments_review_status` ON `moments`;
        ALTER TABLE `moments` DROP COLUMN `review_remark`;
        ALTER TABLE `moments` DROP COLUMN `reviewed_by`;
        ALTER TABLE `moments` DROP COLUMN `reviewed_at`;
        ALTER TABLE `moments` DROP COLUMN `review_status`;
    """
