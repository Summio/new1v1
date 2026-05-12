from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/notification/get', 'GET', '系统通知任务详情', '系统通知模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/notification/get' AND `method` = 'GET');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/notification/update', 'POST', '更新系统通知任务', '系统通知模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/notification/update' AND `method` = 'POST');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/notification/publish', 'POST', '发布系统通知任务', '系统通知模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/notification/publish' AND `method` = 'POST');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/notification/pause', 'POST', '暂停系统通知周期任务', '系统通知模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/notification/pause' AND `method` = 'POST');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/notification/resume', 'POST', '恢复系统通知周期任务', '系统通知模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/notification/resume' AND `method` = 'POST');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/notification/cancel', 'POST', '取消系统通知任务', '系统通知模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/notification/cancel' AND `method` = 'POST');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/notification/delete', 'DELETE', '删除未发送系统通知任务', '系统通知模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/notification/delete' AND `method` = 'DELETE');

        INSERT IGNORE INTO `role_api` (`role_id`, `api_id`)
        SELECT r.`id`, a.`id`
        FROM `role` r
        JOIN `api` a ON a.`tags` = '系统通知模块';
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `role_api`
        WHERE `api_id` IN (
            SELECT `id` FROM `api`
            WHERE `path` IN (
                '/api/v1/notification/get',
                '/api/v1/notification/update',
                '/api/v1/notification/publish',
                '/api/v1/notification/pause',
                '/api/v1/notification/resume',
                '/api/v1/notification/cancel',
                '/api/v1/notification/delete'
            )
        );
        DELETE FROM `api`
        WHERE `path` IN (
            '/api/v1/notification/get',
            '/api/v1/notification/update',
            '/api/v1/notification/publish',
            '/api/v1/notification/pause',
            '/api/v1/notification/resume',
            '/api/v1/notification/cancel',
            '/api/v1/notification/delete'
        );
    """
