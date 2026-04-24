from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user` ADD `anchor_apply_at` DATETIME(6)   COMMENT '主播申请时间';
        ALTER TABLE `app_user` ADD `anchor_tags` JSON   COMMENT '主播标签列表';
        ALTER TABLE `app_user` ADD `anchor_call_price` BIGINT NOT NULL  COMMENT '主播通话价格(分/分钟)' DEFAULT 100;
        ALTER TABLE `app_user` ADD `anchor_apply_status` VARCHAR(20) NOT NULL  COMMENT '主播申请状态 none/pending/approved/rejected' DEFAULT 'none';
        ALTER TABLE `app_user` ADD `anchor_reviewed_at` DATETIME(6)   COMMENT '主播审核时间';
        ALTER TABLE `app_user` ADD `anchor_intro` VARCHAR(500)   COMMENT '主播简介';
        ALTER TABLE `app_user` ADD `anchor_reject_reason` VARCHAR(500)   COMMENT '主播申请拒绝原因';
        ALTER TABLE `app_user` ADD INDEX `idx_app_user_anchor__2309a1` (`anchor_apply_status`);
        UPDATE `app_user` u
        JOIN `anchor` a ON a.`app_user_id` = u.`id`
        SET
            u.`anchor_intro` = COALESCE(a.`intro`, u.`anchor_intro`),
            u.`anchor_tags` = COALESCE(a.`tags`, u.`anchor_tags`),
            u.`anchor_call_price` = COALESCE(a.`call_price`, u.`anchor_call_price`),
            u.`anchor_apply_status` = COALESCE(a.`apply_status`, u.`anchor_apply_status`),
            u.`anchor_apply_at` = COALESCE(a.`apply_at`, u.`anchor_apply_at`),
            u.`anchor_reviewed_at` = COALESCE(a.`reviewed_at`, u.`anchor_reviewed_at`),
            u.`anchor_reject_reason` = COALESCE(a.`reject_reason`, u.`anchor_reject_reason`);
        UPDATE `app_user` u
        JOIN `anchor` a ON a.`app_user_id` = u.`id` AND a.`apply_status` = 'approved'
        SET u.`is_anchor` = 1;
        UPDATE `app_user`
        SET `anchor_apply_status` = 'approved'
        WHERE `is_anchor` = 1 AND (`anchor_apply_status` IS NULL OR `anchor_apply_status` = '' OR `anchor_apply_status` = 'none');
        UPDATE `app_user`
        SET `avatar` = SUBSTRING(`avatar`, LOCATE('/uploads/', `avatar`))
        WHERE `avatar` LIKE 'http%' AND LOCATE('/uploads/', `avatar`) > 0;
        UPDATE `app_user`
        SET `cover_url` = SUBSTRING(`cover_url`, LOCATE('/uploads/', `cover_url`))
        WHERE `cover_url` LIKE 'http%' AND LOCATE('/uploads/', `cover_url`) > 0;"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user` DROP INDEX `idx_app_user_anchor__2309a1`;
        ALTER TABLE `app_user` DROP COLUMN `anchor_apply_at`;
        ALTER TABLE `app_user` DROP COLUMN `anchor_tags`;
        ALTER TABLE `app_user` DROP COLUMN `anchor_call_price`;
        ALTER TABLE `app_user` DROP COLUMN `anchor_apply_status`;
        ALTER TABLE `app_user` DROP COLUMN `anchor_reviewed_at`;
        ALTER TABLE `app_user` DROP COLUMN `anchor_intro`;
        ALTER TABLE `app_user` DROP COLUMN `anchor_reject_reason`;"""
