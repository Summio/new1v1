from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        SET @need_add_initial_profile_completed = (
            SELECT IF(COUNT(*) = 0, 1, 0)
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND COLUMN_NAME = 'initial_profile_completed'
        );

        SET @sql = IF(
            @need_add_initial_profile_completed = 1,
            'ALTER TABLE `app_user` ADD COLUMN `initial_profile_completed` BOOL NOT NULL COMMENT ''是否已完成初始资料'' DEFAULT 0',
            'SELECT 1'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = IF(
            @need_add_initial_profile_completed = 1,
            'UPDATE `app_user` SET `initial_profile_completed` = 1',
            'SELECT 1'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) = 0,
                'CREATE INDEX `idx_app_user_initial_profile_completed` ON `app_user` (`initial_profile_completed`)',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND INDEX_NAME = 'idx_app_user_initial_profile_completed'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        SET @sql = (
            SELECT IF(
                COUNT(*) > 0,
                'DROP INDEX `idx_app_user_initial_profile_completed` ON `app_user`',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND INDEX_NAME = 'idx_app_user_initial_profile_completed'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @sql = (
            SELECT IF(
                COUNT(*) > 0,
                'ALTER TABLE `app_user` DROP COLUMN `initial_profile_completed`',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND COLUMN_NAME = 'initial_profile_completed'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    """
