from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        SET @sql = (
            SELECT IF(
                COUNT(*) = 0,
                'ALTER TABLE `app_user` ADD `coins` BIGINT NOT NULL COMMENT ''金币余额(分)'' DEFAULT 0',
                'ALTER TABLE `app_user` MODIFY COLUMN `coins` BIGINT NOT NULL COMMENT ''金币余额(分)'' DEFAULT 0'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND COLUMN_NAME = 'coins'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) = 0,
                'ALTER TABLE `app_user` ADD `diamonds` BIGINT NOT NULL COMMENT ''钻石余额(分)'' DEFAULT 0',
                'ALTER TABLE `app_user` MODIFY COLUMN `diamonds` BIGINT NOT NULL COMMENT ''钻石余额(分)'' DEFAULT 0'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND COLUMN_NAME = 'diamonds'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) = 0,
                'ALTER TABLE `app_user` ADD `frozen_diamonds` BIGINT NOT NULL COMMENT ''冻结钻石(分)'' DEFAULT 0',
                'ALTER TABLE `app_user` MODIFY COLUMN `frozen_diamonds` BIGINT NOT NULL COMMENT ''冻结钻石(分)'' DEFAULT 0'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND COLUMN_NAME = 'frozen_diamonds'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) = 1,
                'UPDATE `app_user` SET `coins` = `balance` WHERE `coins` = 0 AND `balance` > 0',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND COLUMN_NAME = 'balance'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) = 1,
                'ALTER TABLE `app_user` DROP COLUMN `frozen_balance`',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND COLUMN_NAME = 'frozen_balance'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) = 1,
                'ALTER TABLE `app_user` DROP COLUMN `balance`',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND COLUMN_NAME = 'balance'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        SET @sql = (
            SELECT IF(
                COUNT(*) = 0,
                'ALTER TABLE `app_user` ADD `balance` INT NOT NULL COMMENT ''钱包余额(分)'' DEFAULT 0',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND COLUMN_NAME = 'balance'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) = 0,
                'ALTER TABLE `app_user` ADD `frozen_balance` INT NOT NULL COMMENT ''冻结余额(分)'' DEFAULT 0',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND COLUMN_NAME = 'frozen_balance'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                SUM(CASE WHEN COLUMN_NAME = 'balance' THEN 1 ELSE 0 END) = 1
                AND SUM(CASE WHEN COLUMN_NAME = 'coins' THEN 1 ELSE 0 END) = 1,
                'UPDATE `app_user` SET `balance` = `coins` WHERE `balance` = 0 AND `coins` > 0',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND COLUMN_NAME IN ('balance', 'coins')
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                SUM(CASE WHEN COLUMN_NAME = 'frozen_balance' THEN 1 ELSE 0 END) = 1
                AND SUM(CASE WHEN COLUMN_NAME = 'frozen_diamonds' THEN 1 ELSE 0 END) = 1,
                'UPDATE `app_user` SET `frozen_balance` = `frozen_diamonds` WHERE `frozen_balance` = 0 AND `frozen_diamonds` > 0',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND COLUMN_NAME IN ('frozen_balance', 'frozen_diamonds')
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) = 0,
                'ALTER TABLE `app_user` ADD INDEX `idx_app_user_frozen__90cda7` (`frozen_balance`)',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND INDEX_NAME = 'idx_app_user_frozen__90cda7'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    """
