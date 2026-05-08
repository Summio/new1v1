from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '运营中心', NULL, 'catalog', 'material-symbols:monitoring-outline-rounded', '/operation', 2, 0, 0, 'Layout', 0, '/operation/app-user'
        WHERE NOT EXISTS (
            SELECT 1 FROM `menu` WHERE `path` = '/operation' AND `parent_id` = 0
        );

        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '排行榜', NULL, 'menu', 'material-symbols:leaderboard-outline-rounded', 'ranking', 7, p.`id`, 0, '/operation/ranking', 0, NULL
        FROM `menu` p
        WHERE p.`path` = '/operation' AND p.`parent_id` = 0
          AND NOT EXISTS (
              SELECT 1 FROM `menu` m WHERE m.`path` = 'ranking' AND m.`parent_id` = p.`id`
          );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/ranking/list', 'GET', '排行榜列表', '排行榜'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/ranking/list' AND `method` = 'GET'
        );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/ranking/refresh', 'POST', '刷新排行榜', '排行榜'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/ranking/refresh' AND `method` = 'POST'
        );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/ranking/config', 'GET', '排行榜配置', '排行榜'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/ranking/config' AND `method` = 'GET'
        );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/ranking/config', 'PUT', '更新排行榜配置', '排行榜'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/ranking/config' AND `method` = 'PUT'
        );

        INSERT IGNORE INTO `role_menu` (`role_id`, `menu_id`)
        SELECT r.`id`, m.`id`
        FROM `role` r
        JOIN `menu` m ON m.`path` IN ('/operation', 'ranking');

        INSERT IGNORE INTO `role_api` (`role_id`, `api_id`)
        SELECT r.`id`, a.`id`
        FROM `role` r
        JOIN `api` a ON (
            (a.`path` = '/api/v1/ranking/list' AND a.`method` = 'GET')
            OR (a.`path` = '/api/v1/ranking/refresh' AND a.`method` = 'POST')
            OR (a.`path` = '/api/v1/ranking/config' AND a.`method` IN ('GET', 'PUT'))
        );
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `role_menu`
        WHERE `menu_id` IN (
            SELECT `id` FROM `menu` WHERE `path` = 'ranking' AND `component` = '/operation/ranking'
        );

        DELETE FROM `role_api`
        WHERE `api_id` IN (
            SELECT `id` FROM `api`
            WHERE (`path` = '/api/v1/ranking/list' AND `method` = 'GET')
               OR (`path` = '/api/v1/ranking/refresh' AND `method` = 'POST')
               OR (`path` = '/api/v1/ranking/config' AND `method` IN ('GET', 'PUT'))
        );

        DELETE FROM `api`
        WHERE (`path` = '/api/v1/ranking/list' AND `method` = 'GET')
           OR (`path` = '/api/v1/ranking/refresh' AND `method` = 'POST')
           OR (`path` = '/api/v1/ranking/config' AND `method` IN ('GET', 'PUT'));

        DELETE FROM `menu`
        WHERE `path` = 'ranking' AND `component` = '/operation/ranking';
    """
