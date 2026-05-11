from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE TABLE `feedback` (
            `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
            `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '创建时间',
            `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '更新时间',
            `user_id` BIGINT NOT NULL COMMENT '用户ID',
            `content` VARCHAR(1000) NOT NULL COMMENT '意见反馈内容',
            PRIMARY KEY (`id`),
            KEY `idx_feedback_user_created_at` (`user_id`, `created_at`),
            KEY `idx_feedback_created_at` (`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='意见反馈';

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app/feedback/create', 'POST', '提交意见反馈', '意见反馈模块'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/app/feedback/create' AND `method` = 'POST'
        );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/feedback/list', 'GET', '查看意见反馈列表', '意见反馈模块'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/feedback/list' AND `method` = 'GET'
        );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/feedback/delete', 'DELETE', '删除意见反馈', '意见反馈模块'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/feedback/delete' AND `method` = 'DELETE'
        );

        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '意见反馈', NULL, 'menu', 'material-symbols:feedback-outline-rounded', 'feedback', 9, p.`id`, 0, '/operation/feedback', 0, NULL
        FROM `menu` p
        WHERE p.`path` = '/operation' AND p.`parent_id` = 0
          AND NOT EXISTS (
              SELECT 1 FROM `menu` m WHERE m.`path` = 'feedback' AND m.`parent_id` = p.`id`
          );

        INSERT IGNORE INTO `role_menu` (`role_id`, `menu_id`)
        SELECT r.`id`, m.`id`
        FROM `role` r
        JOIN `menu` m ON m.`path` = 'feedback' AND m.`component` = '/operation/feedback';

        INSERT IGNORE INTO `role_api` (`role_id`, `api_id`)
        SELECT r.`id`, a.`id`
        FROM `role` r
        JOIN `api` a ON (
            (a.`path` = '/api/v1/app/feedback/create' AND a.`method` = 'POST')
            OR (a.`path` = '/api/v1/feedback/list' AND a.`method` = 'GET')
            OR (a.`path` = '/api/v1/feedback/delete' AND a.`method` = 'DELETE')
        );
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `role_menu`
        WHERE `menu_id` IN (
            SELECT `id` FROM `menu` WHERE `path` = 'feedback' AND `component` = '/operation/feedback'
        );

        DELETE FROM `role_api`
        WHERE `api_id` IN (
            SELECT `id` FROM `api`
            WHERE (`path` = '/api/v1/app/feedback/create' AND `method` = 'POST')
               OR (`path` = '/api/v1/feedback/list' AND `method` = 'GET')
               OR (`path` = '/api/v1/feedback/delete' AND `method` = 'DELETE')
        );

        DELETE FROM `api`
        WHERE (`path` = '/api/v1/app/feedback/create' AND `method` = 'POST')
           OR (`path` = '/api/v1/feedback/list' AND `method` = 'GET')
           OR (`path` = '/api/v1/feedback/delete' AND `method` = 'DELETE');

        DELETE FROM `menu`
        WHERE `path` = 'feedback' AND `component` = '/operation/feedback';

        DROP TABLE `feedback`;
    """
