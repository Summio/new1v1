from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        SET @sql = (
            SELECT IF(
                COUNT(*) = 0,
                'ALTER TABLE `user` ADD `avatar` VARCHAR(500) COMMENT ''头像URL''',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'user'
              AND COLUMN_NAME = 'avatar'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        SET @sql = (
            SELECT IF(
                COUNT(*) = 1,
                'ALTER TABLE `user` DROP COLUMN `avatar`',
                'SELECT 1'
            )
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'user'
              AND COLUMN_NAME = 'avatar'
        );
        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    """
