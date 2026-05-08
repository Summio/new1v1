from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user`
            ADD COLUMN `is_certified_user` BOOL NOT NULL DEFAULT 0 COMMENT '是否为真人认证用户',
            ADD COLUMN `certification_status` VARCHAR(20) NOT NULL DEFAULT 'none' COMMENT '真人认证状态 none/pending/approved/rejected',
            ADD COLUMN `certification_apply_at` DATETIME(6) NULL COMMENT '真人认证申请时间',
            ADD COLUMN `certification_reviewed_at` DATETIME(6) NULL COMMENT '真人认证审核时间',
            ADD COLUMN `certification_reject_reason` VARCHAR(500) NULL COMMENT '真人认证拒绝原因',
            ADD COLUMN `certification_face_image` VARCHAR(500) NULL COMMENT '真人认证正面照URL',
            ADD COLUMN `certified_intro` VARCHAR(500) NULL COMMENT '认证用户简介',
            ADD COLUMN `certified_tags` JSON NULL COMMENT '认证用户标签列表',
            ADD COLUMN `certified_call_price` BIGINT NOT NULL DEFAULT 0 COMMENT '认证用户通话价格(分/分钟)';
        UPDATE `app_user`
        SET
            `is_certified_user` = `is_anchor`,
            `certification_status` = CASE
                WHEN `is_anchor` = 1 THEN 'approved'
                ELSE COALESCE(NULLIF(`anchor_apply_status`, ''), 'none')
            END,
            `certification_apply_at` = `anchor_apply_at`,
            `certification_reviewed_at` = `anchor_reviewed_at`,
            `certification_reject_reason` = `anchor_reject_reason`,
            `certification_face_image` = `anchor_apply_face_image`,
            `certified_intro` = `anchor_intro`,
            `certified_tags` = `anchor_tags`,
            `certified_call_price` = CASE
                WHEN `is_anchor` = 1 AND `anchor_call_price` IN (0, 100, 200, 300, 500) THEN `anchor_call_price`
                WHEN `is_anchor` = 1 THEN 100
                ELSE 0
            END;
        ALTER TABLE `app_user`
            DROP COLUMN `is_anchor`,
            DROP COLUMN `anchor_intro`,
            DROP COLUMN `anchor_tags`,
            DROP COLUMN `anchor_call_price`,
            DROP COLUMN `anchor_apply_status`,
            DROP COLUMN `anchor_apply_at`,
            DROP COLUMN `anchor_reviewed_at`,
            DROP COLUMN `anchor_reject_reason`,
            DROP COLUMN `anchor_apply_face_image`;
        CREATE INDEX `idx_app_user_is_certified_user` ON `app_user` (`is_certified_user`);
        CREATE INDEX `idx_app_user_certification_status` ON `app_user` (`certification_status`);
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user`
            ADD COLUMN `is_anchor` BOOL NOT NULL DEFAULT 0 COMMENT '是否为签约主播',
            ADD COLUMN `anchor_intro` VARCHAR(500) NULL COMMENT '主播简介',
            ADD COLUMN `anchor_tags` JSON NULL COMMENT '主播标签列表',
            ADD COLUMN `anchor_call_price` BIGINT NOT NULL DEFAULT 100 COMMENT '主播通话价格(分/分钟)',
            ADD COLUMN `anchor_apply_status` VARCHAR(20) NOT NULL DEFAULT 'none' COMMENT '主播申请状态 none/pending/approved/rejected',
            ADD COLUMN `anchor_apply_at` DATETIME(6) NULL COMMENT '主播申请时间',
            ADD COLUMN `anchor_reviewed_at` DATETIME(6) NULL COMMENT '主播审核时间',
            ADD COLUMN `anchor_reject_reason` VARCHAR(500) NULL COMMENT '主播申请拒绝原因',
            ADD COLUMN `anchor_apply_face_image` VARCHAR(500) NULL COMMENT '主播申请正面照URL';
        UPDATE `app_user`
        SET
            `is_anchor` = `is_certified_user`,
            `anchor_intro` = `certified_intro`,
            `anchor_tags` = `certified_tags`,
            `anchor_call_price` = CASE WHEN `is_certified_user` = 1 THEN `certified_call_price` ELSE 100 END,
            `anchor_apply_status` = `certification_status`,
            `anchor_apply_at` = `certification_apply_at`,
            `anchor_reviewed_at` = `certification_reviewed_at`,
            `anchor_reject_reason` = `certification_reject_reason`,
            `anchor_apply_face_image` = `certification_face_image`;
        ALTER TABLE `app_user`
            DROP COLUMN `is_certified_user`,
            DROP COLUMN `certification_status`,
            DROP COLUMN `certification_apply_at`,
            DROP COLUMN `certification_reviewed_at`,
            DROP COLUMN `certification_reject_reason`,
            DROP COLUMN `certification_face_image`,
            DROP COLUMN `certified_intro`,
            DROP COLUMN `certified_tags`,
            DROP COLUMN `certified_call_price`;
        CREATE INDEX `idx_app_user_is_anchor` ON `app_user` (`is_anchor`);
        CREATE INDEX `idx_app_user_anchor_apply_status` ON `app_user` (`anchor_apply_status`);
    """
