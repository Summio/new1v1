from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        SET @sql = (
            SELECT IF(
                COUNT(*) = 0,
                'ALTER TABLE `call_record` ADD `income_anchor_user_id` BIGINT NULL COMMENT ''本次通话收益主播ID快照''',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'call_record'
              AND COLUMN_NAME = 'income_anchor_user_id'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) = 0,
                'ALTER TABLE `call_record` ADD `anchor_share_bps` INT NOT NULL COMMENT ''本次通话主播分成比例快照（万分比）'' DEFAULT 5000',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'call_record'
              AND COLUMN_NAME = 'anchor_share_bps'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) = 0,
                'ALTER TABLE `call_record` ADD `anchor_income_diamonds` BIGINT NOT NULL COMMENT ''本次通话主播收益钻石(分)'' DEFAULT 0',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'call_record'
              AND COLUMN_NAME = 'anchor_income_diamonds'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) = 0,
                'ALTER TABLE `call_record` ADD `income_settled_at` DATETIME(6) NULL COMMENT ''主播收益结算时间''',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'call_record'
              AND COLUMN_NAME = 'income_settled_at'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'coin_name', '金币', '代币名称-用于充值和消费', CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6)
        FROM DUAL
        WHERE NOT EXISTS (
            SELECT 1 FROM `system_config` WHERE `cfg_key` = 'coin_name'
        );
        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'diamond_name', '钻石', '代币名称-用于主播收益', CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6)
        FROM DUAL
        WHERE NOT EXISTS (
            SELECT 1 FROM `system_config` WHERE `cfg_key` = 'diamond_name'
        );
        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'call_anchor_share_bps', '5000', '视频通话主播分成比例（万分比）', CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6)
        FROM DUAL
        WHERE NOT EXISTS (
            SELECT 1 FROM `system_config` WHERE `cfg_key` = 'call_anchor_share_bps'
        );"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `system_config` WHERE `cfg_key` IN ('coin_name', 'diamond_name', 'call_anchor_share_bps');
        ALTER TABLE `call_record` DROP COLUMN `income_settled_at`;
        ALTER TABLE `call_record` DROP COLUMN `anchor_income_diamonds`;
        ALTER TABLE `call_record` DROP COLUMN `anchor_share_bps`;
        ALTER TABLE `call_record` DROP COLUMN `income_anchor_user_id`;"""
