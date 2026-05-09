from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE TABLE IF NOT EXISTS `ranking_snapshot` (
            `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
            `created_at` DATETIME(6) NOT NULL COMMENT '创建时间',
            `updated_at` DATETIME(6) NOT NULL COMMENT '更新时间',
            `board` VARCHAR(20) NOT NULL COMMENT '榜单 charm/wealth/invite',
            `period` VARCHAR(20) NOT NULL COMMENT '周期 day/week/month',
            `period_start` DATETIME(6) NOT NULL COMMENT '统计开始时间',
            `period_end` DATETIME(6) NOT NULL COMMENT '统计结束时间',
            `user_id` BIGINT NOT NULL COMMENT 'App 用户ID',
            `rank` INT NOT NULL COMMENT '排名',
            `score` DECIMAL(18,2) NOT NULL DEFAULT 0 COMMENT '真实榜单分数',
            `computed_at` DATETIME(6) NOT NULL COMMENT '快照计算时间',
            `source_summary` JSON NULL COMMENT '来源摘要',
            UNIQUE KEY `uidx_ranking_snapshot_period_user` (`board`, `period`, `period_start`, `user_id`),
            KEY `idx_ranking_snapshot_period_rank` (`board`, `period`, `period_start`, `rank`),
            KEY `idx_ranking_snapshot_board` (`board`),
            KEY `idx_ranking_snapshot_period` (`period`),
            KEY `idx_ranking_snapshot_period_start` (`period_start`),
            KEY `idx_ranking_snapshot_user_id` (`user_id`),
            KEY `idx_ranking_snapshot_rank` (`rank`),
            KEY `idx_ranking_snapshot_computed_at` (`computed_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='排行榜快照';

        CREATE INDEX `idx_call_record_created_income_anchor` ON `call_record` (`created_at`, `income_anchor_user_id`);
        CREATE INDEX `idx_call_record_created_payer` ON `call_record` (`created_at`, `payer_user_id`);
        CREATE INDEX `idx_call_record_created_caller` ON `call_record` (`created_at`, `caller_id`);
        CREATE INDEX `idx_gift_record_created_receiver` ON `gift_record` (`created_at`, `receiver_id`);
        CREATE INDEX `idx_gift_record_created_sender` ON `gift_record` (`created_at`, `sender_id`);
        CREATE INDEX `idx_im_text_created_receiver` ON `im_text_message_charge_record` (`created_at`, `receiver_id`);
        CREATE INDEX `idx_im_text_created_sender` ON `im_text_message_charge_record` (`created_at`, `sender_id`);

        INSERT INTO `system_config` (`created_at`, `updated_at`, `cfg_key`, `cfg_value`, `description`)
        VALUES (NOW(6), NOW(6), 'ranking_app_display_limit', '20', 'App排行榜展示数量')
        ON DUPLICATE KEY UPDATE `cfg_value` = `cfg_value`;
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `system_config` WHERE `cfg_key` = 'ranking_app_display_limit';
        DROP INDEX `idx_im_text_created_sender` ON `im_text_message_charge_record`;
        DROP INDEX `idx_im_text_created_receiver` ON `im_text_message_charge_record`;
        DROP INDEX `idx_gift_record_created_sender` ON `gift_record`;
        DROP INDEX `idx_gift_record_created_receiver` ON `gift_record`;
        DROP INDEX `idx_call_record_created_caller` ON `call_record`;
        DROP INDEX `idx_call_record_created_payer` ON `call_record`;
        DROP INDEX `idx_call_record_created_income_anchor` ON `call_record`;
        DROP TABLE IF EXISTS `ranking_snapshot`;
    """
