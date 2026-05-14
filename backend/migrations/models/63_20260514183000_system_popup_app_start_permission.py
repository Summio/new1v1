from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app/popups/startup', 'POST', '获取App启动弹窗', '弹窗提示模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/app/popups/startup' AND `method` = 'POST');

        INSERT IGNORE INTO `role_api` (`role_id`, `api_id`)
        SELECT r.`id`, a.`id`
        FROM `role` r
        JOIN `api` a ON a.`path` = '/api/v1/app/popups/startup' AND a.`method` = 'POST';
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `role_api`
        WHERE `api_id` IN (
            SELECT `id` FROM `api` WHERE `path` = '/api/v1/app/popups/startup' AND `method` = 'POST'
        );
        DELETE FROM `api` WHERE `path` = '/api/v1/app/popups/startup' AND `method` = 'POST';
    """
