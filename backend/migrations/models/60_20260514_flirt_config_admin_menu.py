from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '设置', NULL, 'catalog', 'material-symbols:tune-rounded', '/settings', 4, 0, 0, 'Layout', 0, '/settings/recharge-config'
        WHERE NOT EXISTS (
            SELECT 1 FROM `menu` WHERE `path` = '/settings' AND `parent_id` = 0
        );

        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '搭讪配置', NULL, 'menu', 'material-symbols:forum-outline-rounded', 'flirt-config', 4, p.`id`, 0, '/system/flirt-config', 0, NULL
        FROM `menu` p
        WHERE p.`path` = '/settings' AND p.`parent_id` = 0
          AND NOT EXISTS (
              SELECT 1 FROM `menu` m WHERE m.`path` = 'flirt-config' AND m.`parent_id` = p.`id`
          );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/apis/system/flirt-config', 'GET', '获取搭讪配置', '系统配置-搭讪'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/apis/system/flirt-config' AND `method` = 'GET'
        );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/apis/system/flirt-config', 'PUT', '更新搭讪配置', '系统配置-搭讪'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/apis/system/flirt-config' AND `method` = 'PUT'
        );

        INSERT IGNORE INTO `role_menu` (`role_id`, `menu_id`)
        SELECT r.`id`, m.`id`
        FROM `role` r
        JOIN `menu` m ON (
            (m.`path` = '/settings' AND m.`parent_id` = 0)
            OR (m.`path` = 'flirt-config' AND m.`component` = '/system/flirt-config')
        );

        INSERT IGNORE INTO `role_api` (`role_id`, `api_id`)
        SELECT r.`id`, a.`id`
        FROM `role` r
        JOIN `api` a ON a.`path` = '/api/v1/apis/system/flirt-config' AND a.`method` IN ('GET', 'PUT');
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `role_menu`
        WHERE `menu_id` IN (
            SELECT `id` FROM `menu` WHERE `path` = 'flirt-config' AND `component` = '/system/flirt-config'
        );

        DELETE FROM `role_api`
        WHERE `api_id` IN (
            SELECT `id` FROM `api`
            WHERE `path` = '/api/v1/apis/system/flirt-config' AND `method` IN ('GET', 'PUT')
        );

        DELETE FROM `api`
        WHERE `path` = '/api/v1/apis/system/flirt-config' AND `method` IN ('GET', 'PUT');

        DELETE FROM `menu`
        WHERE `path` = 'flirt-config' AND `component` = '/system/flirt-config';
    """
