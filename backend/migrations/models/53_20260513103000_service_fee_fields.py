from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `call_record`
            ADD COLUMN `service_fee_threshold_minutes` INT NOT NULL DEFAULT 0 COMMENT '通话手续费阈值分钟快照',
            ADD COLUMN `service_fee_rate_bps` INT NOT NULL DEFAULT 0 COMMENT '通话手续费比例快照(万分比)',
            ADD COLUMN `service_fee_processed_chargeable_minutes` INT NOT NULL DEFAULT 0 COMMENT '已处理手续费分钟数',
            ADD COLUMN `service_fee_payer_expected_coins` DECIMAL(18,2) NOT NULL DEFAULT 0 COMMENT '付费方理论手续费金币',
            ADD COLUMN `service_fee_payer_actual_coins` DECIMAL(18,2) NOT NULL DEFAULT 0 COMMENT '付费方实扣手续费金币',
            ADD COLUMN `service_fee_payer_status` VARCHAR(32) NULL COMMENT '付费方手续费状态',
            ADD COLUMN `service_fee_payer_settled_at` DATETIME(6) NULL COMMENT '付费方手续费结算时间',
            ADD COLUMN `service_fee_income_expected_diamonds` DECIMAL(18,2) NOT NULL DEFAULT 0 COMMENT '收益方理论手续费钻石',
            ADD COLUMN `service_fee_income_actual_diamonds` DECIMAL(18,2) NOT NULL DEFAULT 0 COMMENT '收益方实扣手续费钻石',
            ADD COLUMN `service_fee_income_status` VARCHAR(32) NULL COMMENT '收益方手续费状态',
            ADD COLUMN `service_fee_income_settled_at` DATETIME(6) NULL COMMENT '收益方手续费结算时间';

        ALTER TABLE `gift_record`
            ADD COLUMN `service_fee_threshold_coins` BIGINT NOT NULL DEFAULT 0 COMMENT '礼物手续费阈值快照(金币)',
            ADD COLUMN `service_fee_rate_bps` INT NOT NULL DEFAULT 0 COMMENT '礼物手续费比例快照(万分比)',
            ADD COLUMN `service_fee_sender_expected_coins` DECIMAL(18,2) NOT NULL DEFAULT 0 COMMENT '送礼方理论手续费金币',
            ADD COLUMN `service_fee_sender_actual_coins` DECIMAL(18,2) NOT NULL DEFAULT 0 COMMENT '送礼方实扣手续费金币',
            ADD COLUMN `service_fee_sender_status` VARCHAR(32) NULL COMMENT '送礼方手续费状态',
            ADD COLUMN `service_fee_sender_settled_at` DATETIME(6) NULL COMMENT '送礼方手续费结算时间';

        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'call_service_fee_enabled', '0', '通话手续费开关', CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6)
        FROM DUAL
        WHERE NOT EXISTS (SELECT 1 FROM `system_config` WHERE `cfg_key` = 'call_service_fee_enabled');

        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'call_service_fee_threshold_minutes', '0', '通话手续费阈值分钟', CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6)
        FROM DUAL
        WHERE NOT EXISTS (SELECT 1 FROM `system_config` WHERE `cfg_key` = 'call_service_fee_threshold_minutes');

        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'call_service_fee_rate_bps', '0', '通话手续费比例（万分比）', CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6)
        FROM DUAL
        WHERE NOT EXISTS (SELECT 1 FROM `system_config` WHERE `cfg_key` = 'call_service_fee_rate_bps');

        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'gift_service_fee_enabled', '0', '礼物手续费开关', CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6)
        FROM DUAL
        WHERE NOT EXISTS (SELECT 1 FROM `system_config` WHERE `cfg_key` = 'gift_service_fee_enabled');

        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'gift_service_fee_threshold_coins', '0', '礼物手续费单价阈值', CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6)
        FROM DUAL
        WHERE NOT EXISTS (SELECT 1 FROM `system_config` WHERE `cfg_key` = 'gift_service_fee_threshold_coins');

        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'gift_service_fee_rate_bps', '0', '礼物手续费比例（万分比）', CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6)
        FROM DUAL
        WHERE NOT EXISTS (SELECT 1 FROM `system_config` WHERE `cfg_key` = 'gift_service_fee_rate_bps');
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `system_config`
        WHERE `cfg_key` IN (
            'call_service_fee_enabled',
            'call_service_fee_threshold_minutes',
            'call_service_fee_rate_bps',
            'gift_service_fee_enabled',
            'gift_service_fee_threshold_coins',
            'gift_service_fee_rate_bps'
        );

        ALTER TABLE `gift_record`
            DROP COLUMN `service_fee_threshold_coins`,
            DROP COLUMN `service_fee_rate_bps`,
            DROP COLUMN `service_fee_sender_expected_coins`,
            DROP COLUMN `service_fee_sender_actual_coins`,
            DROP COLUMN `service_fee_sender_status`,
            DROP COLUMN `service_fee_sender_settled_at`;

        ALTER TABLE `call_record`
            DROP COLUMN `service_fee_threshold_minutes`,
            DROP COLUMN `service_fee_rate_bps`,
            DROP COLUMN `service_fee_processed_chargeable_minutes`,
            DROP COLUMN `service_fee_payer_expected_coins`,
            DROP COLUMN `service_fee_payer_actual_coins`,
            DROP COLUMN `service_fee_payer_status`,
            DROP COLUMN `service_fee_payer_settled_at`,
            DROP COLUMN `service_fee_income_expected_diamonds`,
            DROP COLUMN `service_fee_income_actual_diamonds`,
            DROP COLUMN `service_fee_income_status`,
            DROP COLUMN `service_fee_income_settled_at`;
    """
