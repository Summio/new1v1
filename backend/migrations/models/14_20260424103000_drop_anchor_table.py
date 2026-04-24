from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        DROP TABLE IF EXISTS `anchor`;"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE TABLE IF NOT EXISTS `anchor` (
            `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
            `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '创建时间',
            `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '更新时间',
            `app_user_id` BIGINT NOT NULL UNIQUE COMMENT '主播关联用户ID',
            `is_online` BOOL NOT NULL DEFAULT 0 COMMENT '是否在线',
            `call_price` BIGINT NOT NULL DEFAULT 100 COMMENT '每分钟通话价格(分)',
            `intro` VARCHAR(500) COMMENT '主播简介',
            `tags` JSON COMMENT '标签列表',
            `avatar` VARCHAR(500) COMMENT '头像URL',
            `online_at` DATETIME(6) COMMENT '最近上线时间',
            `apply_status` VARCHAR(20) NOT NULL DEFAULT 'pending' COMMENT 'pending/approved/rejected',
            `apply_at` DATETIME(6) COMMENT '申请时间',
            `reviewed_at` DATETIME(6) COMMENT '审核时间',
            `reject_reason` VARCHAR(500) COMMENT '拒绝原因',
            CONSTRAINT `fk_anchor_app_user_1090901a` FOREIGN KEY (`app_user_id`) REFERENCES `app_user` (`id`) ON DELETE CASCADE,
            KEY `idx_anchor_created_d63aae` (`created_at`),
            KEY `idx_anchor_updated_db14f9` (`updated_at`),
            KEY `idx_anchor_is_onli_6ef924` (`is_online`),
            KEY `idx_anchor_apply_s_052374` (`apply_status`)
        );"""
