from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        SET @sql = (
            SELECT IF(
                COUNT(*) > 0,
                'DROP INDEX `idx_call_record_income_created` ON `call_record`',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'call_record'
              AND INDEX_NAME = 'idx_call_record_income_created'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) > 0,
                'DROP INDEX `idx_call_record_created_income_anchor` ON `call_record`',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'call_record'
              AND INDEX_NAME = 'idx_call_record_created_income_anchor'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) > 0,
                'ALTER TABLE `call_record` CHANGE COLUMN `income_anchor_user_id` `income_certified_user_id` BIGINT NULL COMMENT ''本次通话收益认证用户ID快照''',
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
                COUNT(*) > 0,
                'ALTER TABLE `call_record` CHANGE COLUMN `anchor_share_bps` `certified_user_share_bps` INT NOT NULL COMMENT ''本次通话认证用户分成比例快照（万分比）'' DEFAULT 5000',
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
                COUNT(*) > 0,
                'ALTER TABLE `call_record` CHANGE COLUMN `anchor_income_diamonds` `certified_user_income_diamonds` BIGINT NOT NULL COMMENT ''本次通话认证用户收益钻石'' DEFAULT 0',
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
                COUNT(*) > 0,
                'ALTER TABLE `gift_record` CHANGE COLUMN `anchor_share_bps` `certified_user_share_bps` INT NOT NULL COMMENT ''认证用户分成比例快照(万分比)'' DEFAULT 10000',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'gift_record'
              AND COLUMN_NAME = 'anchor_share_bps'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) > 0,
                'ALTER TABLE `gift_record` CHANGE COLUMN `anchor_income_diamonds` `certified_user_income_diamonds` DECIMAL(18,2) NOT NULL COMMENT ''认证用户礼物收益钻石'' DEFAULT 0',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'gift_record'
              AND COLUMN_NAME = 'anchor_income_diamonds'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) > 0,
                'ALTER TABLE `im_text_message_charge_record` CHANGE COLUMN `anchor_share_bps` `certified_user_share_bps` INT NOT NULL COMMENT ''认证用户分成比例快照(万分比)'' DEFAULT 5000',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'im_text_message_charge_record'
              AND COLUMN_NAME = 'anchor_share_bps'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) > 0,
                'ALTER TABLE `im_text_message_charge_record` CHANGE COLUMN `anchor_income_diamonds` `certified_user_income_diamonds` DECIMAL(18,2) NOT NULL COMMENT ''认证用户收益钻石'' DEFAULT 0',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'im_text_message_charge_record'
              AND COLUMN_NAME = 'anchor_income_diamonds'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        UPDATE `system_config`
        SET `cfg_key` = 'call_certified_user_share_bps',
            `description` = '视频通话认证用户分成比例（万分比）'
        WHERE `cfg_key` = 'call_anchor_share_bps'
          AND NOT EXISTS (
              SELECT 1 FROM (
                  SELECT `id` FROM `system_config`
                  WHERE `cfg_key` = 'call_certified_user_share_bps'
              ) AS existing_call_share
          );
        UPDATE `system_config`
        SET `cfg_key` = 'gift_certified_user_share_bps',
            `description` = '礼物认证用户分成比例（万分比）'
        WHERE `cfg_key` = 'gift_anchor_share_bps'
          AND NOT EXISTS (
              SELECT 1 FROM (
                  SELECT `id` FROM `system_config`
                  WHERE `cfg_key` = 'gift_certified_user_share_bps'
              ) AS existing_gift_share
          );
        UPDATE `system_config`
        SET `cfg_key` = 'im_text_message_certified_user_share_bps',
            `description` = '文字聊天认证用户分成比例'
        WHERE `cfg_key` = 'im_text_message_anchor_share_bps'
          AND NOT EXISTS (
              SELECT 1 FROM (
                  SELECT `id` FROM `system_config`
                  WHERE `cfg_key` = 'im_text_message_certified_user_share_bps'
              ) AS existing_im_text_share
          );
        DELETE FROM `system_config`
        WHERE `cfg_key` IN (
            'call_anchor_share_bps',
            'gift_anchor_share_bps',
            'im_text_message_anchor_share_bps'
        );

        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'call_certified_user_share_bps', '5000', '视频通话认证用户分成比例（万分比）', CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6)
        FROM DUAL
        WHERE NOT EXISTS (
            SELECT 1 FROM `system_config` WHERE `cfg_key` = 'call_certified_user_share_bps'
        );
        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'gift_certified_user_share_bps', '5000', '礼物认证用户分成比例（万分比）', CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6)
        FROM DUAL
        WHERE NOT EXISTS (
            SELECT 1 FROM `system_config` WHERE `cfg_key` = 'gift_certified_user_share_bps'
        );
        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'im_text_message_certified_user_share_bps', '5000', '文字聊天认证用户分成比例', CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6)
        FROM DUAL
        WHERE NOT EXISTS (
            SELECT 1 FROM `system_config` WHERE `cfg_key` = 'im_text_message_certified_user_share_bps'
        );

        SET @sql = (
            SELECT IF(
                COUNT(*) = 0,
                'CREATE INDEX `idx_call_record_income_certified_created` ON `call_record` (`income_certified_user_id`, `created_at`)',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'call_record'
              AND INDEX_NAME = 'idx_call_record_income_certified_created'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) = 0,
                'CREATE INDEX `idx_call_record_created_income_certified` ON `call_record` (`created_at`, `income_certified_user_id`)',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'call_record'
              AND INDEX_NAME = 'idx_call_record_created_income_certified'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) = 0,
                'CREATE INDEX `idx_app_user_certified_rec_perf` ON `app_user` (`status`, `is_certified_user`, `is_recommended`, `recommend_weight`, `certification_reviewed_at`, `id`)',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND INDEX_NAME = 'idx_app_user_certified_rec_perf'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) = 0,
                'CREATE INDEX `idx_app_user_certified_new_perf` ON `app_user` (`status`, `is_certified_user`, `certification_reviewed_at`, `id`)',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND INDEX_NAME = 'idx_app_user_certified_new_perf'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DROP INDEX `idx_app_user_certified_new_perf` ON `app_user`;
        DROP INDEX `idx_app_user_certified_rec_perf` ON `app_user`;
        DROP INDEX `idx_call_record_created_income_certified` ON `call_record`;
        DROP INDEX `idx_call_record_income_certified_created` ON `call_record`;

        UPDATE `system_config`
        SET `cfg_key` = 'call_anchor_share_bps',
            `description` = '视频通话主播分成比例（万分比）'
        WHERE `cfg_key` = 'call_certified_user_share_bps';
        UPDATE `system_config`
        SET `cfg_key` = 'gift_anchor_share_bps',
            `description` = '礼物主播分成比例（万分比）'
        WHERE `cfg_key` = 'gift_certified_user_share_bps';
        UPDATE `system_config`
        SET `cfg_key` = 'im_text_message_anchor_share_bps',
            `description` = '文字聊天主播分成比例'
        WHERE `cfg_key` = 'im_text_message_certified_user_share_bps';

        ALTER TABLE `im_text_message_charge_record` CHANGE COLUMN `certified_user_income_diamonds` `anchor_income_diamonds` DECIMAL(18,2) NOT NULL COMMENT '主播收益钻石' DEFAULT 0;
        ALTER TABLE `im_text_message_charge_record` CHANGE COLUMN `certified_user_share_bps` `anchor_share_bps` INT NOT NULL COMMENT '主播分成比例快照(万分比)' DEFAULT 5000;
        ALTER TABLE `gift_record` CHANGE COLUMN `certified_user_income_diamonds` `anchor_income_diamonds` DECIMAL(18,2) NOT NULL COMMENT '主播礼物收益钻石' DEFAULT 0;
        ALTER TABLE `gift_record` CHANGE COLUMN `certified_user_share_bps` `anchor_share_bps` INT NOT NULL COMMENT '主播分成比例快照(万分比)' DEFAULT 10000;
        ALTER TABLE `call_record` CHANGE COLUMN `certified_user_income_diamonds` `anchor_income_diamonds` BIGINT NOT NULL COMMENT '本次通话主播收益钻石(分)' DEFAULT 0;
        ALTER TABLE `call_record` CHANGE COLUMN `certified_user_share_bps` `anchor_share_bps` INT NOT NULL COMMENT '本次通话主播分成比例快照（万分比）' DEFAULT 5000;
        ALTER TABLE `call_record` CHANGE COLUMN `income_certified_user_id` `income_anchor_user_id` BIGINT NULL COMMENT '本次通话收益主播ID快照';
        CREATE INDEX `idx_call_record_income_created` ON `call_record` (`income_anchor_user_id`, `created_at`);
        CREATE INDEX `idx_call_record_created_income_anchor` ON `call_record` (`created_at`, `income_anchor_user_id`);
    """
