from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `call_record`
            ADD COLUMN `service_fee_payer_rate_bps` INT NOT NULL DEFAULT 0 COMMENT '通话付费方手续费比例快照(万分比)' AFTER `service_fee_rate_bps`,
            ADD COLUMN `service_fee_income_rate_bps` INT NOT NULL DEFAULT 0 COMMENT '通话收益方手续费比例快照(万分比)' AFTER `service_fee_payer_rate_bps`;

        UPDATE `call_record`
        SET
            `service_fee_payer_rate_bps` = `service_fee_rate_bps`,
            `service_fee_income_rate_bps` = `service_fee_rate_bps`
        WHERE `service_fee_rate_bps` IS NOT NULL;

        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT
            'call_service_fee_payer_rate_bps',
            COALESCE((SELECT `cfg_value` FROM `system_config` WHERE `cfg_key` = 'call_service_fee_rate_bps' LIMIT 1), '0'),
            '通话付费方手续费比例（万分比）',
            CURRENT_TIMESTAMP(6),
            CURRENT_TIMESTAMP(6)
        FROM DUAL
        WHERE NOT EXISTS (
            SELECT 1 FROM `system_config` WHERE `cfg_key` = 'call_service_fee_payer_rate_bps'
        );

        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT
            'call_service_fee_income_rate_bps',
            COALESCE((SELECT `cfg_value` FROM `system_config` WHERE `cfg_key` = 'call_service_fee_rate_bps' LIMIT 1), '0'),
            '通话收益方手续费比例（万分比）',
            CURRENT_TIMESTAMP(6),
            CURRENT_TIMESTAMP(6)
        FROM DUAL
        WHERE NOT EXISTS (
            SELECT 1 FROM `system_config` WHERE `cfg_key` = 'call_service_fee_income_rate_bps'
        );
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `system_config`
        WHERE `cfg_key` IN (
            'call_service_fee_payer_rate_bps',
            'call_service_fee_income_rate_bps'
        );

        ALTER TABLE `call_record`
            DROP COLUMN `service_fee_income_rate_bps`,
            DROP COLUMN `service_fee_payer_rate_bps`;
    """
