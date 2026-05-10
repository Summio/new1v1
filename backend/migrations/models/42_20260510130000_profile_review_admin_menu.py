from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '运营中心', NULL, 'catalog', 'material-symbols:monitoring-outline-rounded', '/operation', 2, 0, 0, 'Layout', 0, '/operation/app-user'
        WHERE NOT EXISTS (
            SELECT 1 FROM `menu` WHERE `path` = '/operation' AND `parent_id` = 0
        );

        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '资料编辑审核', NULL, 'menu', 'material-symbols:fact-check-outline-rounded', 'profile-review', 8, p.`id`, 0, '/operation/profile-review', 0, NULL
        FROM `menu` p
        WHERE p.`path` = '/operation' AND p.`parent_id` = 0
          AND NOT EXISTS (
              SELECT 1 FROM `menu` m WHERE m.`path` = 'profile-review'
          );

        UPDATE `menu` m
        JOIN `menu` p ON p.`path` = '/operation' AND p.`parent_id` = 0
        SET
            m.`name` = '资料编辑审核',
            m.`menu_type` = 'menu',
            m.`icon` = 'material-symbols:fact-check-outline-rounded',
            m.`order` = 8,
            m.`parent_id` = p.`id`,
            m.`is_hidden` = 0,
            m.`component` = '/operation/profile-review',
            m.`keepalive` = 0,
            m.`redirect` = NULL
        WHERE m.`path` = 'profile-review';

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app_user/profile-review/list', 'GET', '查看App用户资料编辑申请列表', 'App用户模块'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/app_user/profile-review/list' AND `method` = 'GET'
        );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app_user/profile-review/get', 'GET', '查看App用户资料编辑申请详情', 'App用户模块'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/app_user/profile-review/get' AND `method` = 'GET'
        );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app_user/profile-review/item/review', 'POST', '审核App用户资料编辑单项', 'App用户模块'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/app_user/profile-review/item/review' AND `method` = 'POST'
        );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app_user/profile-review/approve-all', 'POST', '全部通过App用户资料编辑申请', 'App用户模块'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/app_user/profile-review/approve-all' AND `method` = 'POST'
        );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app_user/profile-review/reject-all', 'POST', '全部驳回App用户资料编辑申请', 'App用户模块'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/app_user/profile-review/reject-all' AND `method` = 'POST'
        );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app_user/profile-review/complete', 'POST', '完成App用户资料编辑审核', 'App用户模块'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/app_user/profile-review/complete' AND `method` = 'POST'
        );

        INSERT IGNORE INTO `role_menu` (`role_id`, `menu_id`)
        SELECT r.`id`, m.`id`
        FROM `role` r
        JOIN `menu` m ON m.`path` IN ('/operation', 'profile-review');

        INSERT IGNORE INTO `role_api` (`role_id`, `api_id`)
        SELECT r.`id`, a.`id`
        FROM `role` r
        JOIN `api` a ON (
            (a.`path` = '/api/v1/app_user/profile-review/list' AND a.`method` = 'GET')
            OR (a.`path` = '/api/v1/app_user/profile-review/get' AND a.`method` = 'GET')
            OR (a.`path` = '/api/v1/app_user/profile-review/item/review' AND a.`method` = 'POST')
            OR (a.`path` = '/api/v1/app_user/profile-review/approve-all' AND a.`method` = 'POST')
            OR (a.`path` = '/api/v1/app_user/profile-review/reject-all' AND a.`method` = 'POST')
            OR (a.`path` = '/api/v1/app_user/profile-review/complete' AND a.`method` = 'POST')
        );
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `role_menu`
        WHERE `menu_id` IN (
            SELECT `id` FROM `menu` WHERE `path` = 'profile-review' AND `component` = '/operation/profile-review'
        );

        DELETE FROM `role_api`
        WHERE `api_id` IN (
            SELECT `id` FROM `api`
            WHERE (`path` = '/api/v1/app_user/profile-review/list' AND `method` = 'GET')
               OR (`path` = '/api/v1/app_user/profile-review/get' AND `method` = 'GET')
               OR (`path` = '/api/v1/app_user/profile-review/item/review' AND `method` = 'POST')
               OR (`path` = '/api/v1/app_user/profile-review/approve-all' AND `method` = 'POST')
               OR (`path` = '/api/v1/app_user/profile-review/reject-all' AND `method` = 'POST')
               OR (`path` = '/api/v1/app_user/profile-review/complete' AND `method` = 'POST')
        );

        DELETE FROM `api`
        WHERE (`path` = '/api/v1/app_user/profile-review/list' AND `method` = 'GET')
           OR (`path` = '/api/v1/app_user/profile-review/get' AND `method` = 'GET')
           OR (`path` = '/api/v1/app_user/profile-review/item/review' AND `method` = 'POST')
           OR (`path` = '/api/v1/app_user/profile-review/approve-all' AND `method` = 'POST')
           OR (`path` = '/api/v1/app_user/profile-review/reject-all' AND `method` = 'POST')
           OR (`path` = '/api/v1/app_user/profile-review/complete' AND `method` = 'POST');

        DELETE FROM `menu`
        WHERE `path` = 'profile-review' AND `component` = '/operation/profile-review';
    """
