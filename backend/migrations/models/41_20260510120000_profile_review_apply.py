from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE TABLE IF NOT EXISTS `app_user_profile_review_apply` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `user_id` BIGINT NOT NULL COMMENT 'App用户ID',
    `status` VARCHAR(20) NOT NULL DEFAULT 'pending' COMMENT 'pending/reviewing/completed/cancelled',
    `before_snapshot` JSON NULL COMMENT '提交前资料快照',
    `after_snapshot` JSON NULL COMMENT '提交后资料快照',
    `review_items` JSON NULL COMMENT '审核项列表',
    `submitted_at` DATETIME(6) NULL COMMENT '提交时间',
    `completed_at` DATETIME(6) NULL COMMENT '完成时间',
    `completed_by` BIGINT NULL COMMENT '完成审核的后台用户ID',
    `review_remark` VARCHAR(500) NULL COMMENT '审核备注',
    KEY `idx_profile_review_user_status` (`user_id`, `status`),
    KEY `idx_profile_review_status_created_at` (`status`, `created_at`),
    KEY `idx_profile_review_created_at` (`created_at`)
        ) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DROP TABLE IF EXISTS `app_user_profile_review_apply`;"""
