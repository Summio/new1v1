from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '运营中心', NULL, 'catalog', 'material-symbols:monitoring-outline-rounded', '/operation', 2, 0, 0, 'Layout', 0, '/operation/app-user'
        WHERE NOT EXISTS (
            SELECT 1 FROM `menu` WHERE `path` = '/operation' AND `parent_id` = 0
        );

        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '动态管理', NULL, 'menu', 'material-symbols:dynamic-feed-rounded', 'moment', 4, p.`id`, 0, '/operation/moment', 0, NULL
        FROM `menu` p
        WHERE p.`path` = '/operation' AND p.`parent_id` = 0
          AND NOT EXISTS (
              SELECT 1 FROM `menu` m WHERE m.`path` = 'moment' AND m.`parent_id` = p.`id`
          );

        INSERT IGNORE INTO `role_menu` (`role_id`, `menu_id`)
        SELECT r.`id`, m.`id`
        FROM `role` r
        JOIN `menu` m ON m.`path` IN ('/operation', 'moment');

        INSERT IGNORE INTO `role_api` (`role_id`, `api_id`)
        SELECT r.`id`, a.`id`
        FROM `role` r
        JOIN `api` a ON a.`path` IN ('/api/v1/moment/list', '/api/v1/moment/delete');
        """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `role_menu`
        WHERE `menu_id` IN (
            SELECT `id` FROM `menu` WHERE `path` = 'moment' AND `component` = '/operation/moment'
        );

        DELETE FROM `role_api`
        WHERE `api_id` IN (
            SELECT `id` FROM `api` WHERE `path` IN ('/api/v1/moment/list', '/api/v1/moment/delete')
        );

        DELETE FROM `menu`
        WHERE `path` = 'moment' AND `component` = '/operation/moment';
        """
