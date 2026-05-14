from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT
            'flirt_filter_same_gender_enabled',
            'true',
            '搭讪配置-过滤同性别',
            CURRENT_TIMESTAMP(6),
            CURRENT_TIMESTAMP(6)
        FROM DUAL
        WHERE NOT EXISTS (
            SELECT 1 FROM `system_config` WHERE `cfg_key` = 'flirt_filter_same_gender_enabled'
        );

        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT
            'flirt_filter_certified_user_enabled',
            'true',
            '搭讪配置-过滤真人认证用户',
            CURRENT_TIMESTAMP(6),
            CURRENT_TIMESTAMP(6)
        FROM DUAL
        WHERE NOT EXISTS (
            SELECT 1 FROM `system_config` WHERE `cfg_key` = 'flirt_filter_certified_user_enabled'
        );
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `system_config`
        WHERE `cfg_key` IN (
            'flirt_filter_same_gender_enabled',
            'flirt_filter_certified_user_enabled'
        );
    """
