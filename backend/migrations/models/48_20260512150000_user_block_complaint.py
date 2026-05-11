from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE TABLE `user_block` (
            `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
            `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '创建时间',
            `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '更新时间',
            `blocker_id` BIGINT NOT NULL COMMENT '拉黑发起用户ID',
            `blocked_id` BIGINT NOT NULL COMMENT '被拉黑用户ID',
            `reason` VARCHAR(255) NULL COMMENT '拉黑备注',
            PRIMARY KEY (`id`),
            UNIQUE KEY `uniq_user_block_pair` (`blocker_id`, `blocked_id`),
            KEY `idx_user_block_blocker_created_at` (`blocker_id`, `created_at`),
            KEY `idx_user_block_blocked_id` (`blocked_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='用户黑名单关系';

        CREATE TABLE `user_complaint` (
            `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
            `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '创建时间',
            `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '更新时间',
            `complainant_id` BIGINT NOT NULL COMMENT '投诉人用户ID',
            `target_user_id` BIGINT NOT NULL COMMENT '被投诉用户ID',
            `scene` VARCHAR(32) NOT NULL COMMENT '投诉来源',
            `reason` VARCHAR(64) NOT NULL COMMENT '投诉原因',
            `content` VARCHAR(1000) NOT NULL COMMENT '投诉补充说明',
            `status` VARCHAR(32) NOT NULL DEFAULT 'pending' COMMENT '处理状态',
            `handle_remark` VARCHAR(1000) NULL COMMENT '最后处理备注',
            `handled_by` BIGINT NULL COMMENT '最后处理管理员ID',
            `handled_at` DATETIME(6) NULL COMMENT '最后处理时间',
            PRIMARY KEY (`id`),
            KEY `idx_user_complaint_target_status` (`target_user_id`, `status`),
            KEY `idx_user_complaint_complainant_created_at` (`complainant_id`, `created_at`),
            KEY `idx_user_complaint_status_created_at` (`status`, `created_at`),
            KEY `idx_user_complaint_created_at` (`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='用户投诉记录';

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app/user/block', 'POST', '拉黑用户', '黑名单模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/app/user/block' AND `method` = 'POST');

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app/user/block', 'DELETE', '解除拉黑用户', '黑名单模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/app/user/block' AND `method` = 'DELETE');

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app/user/block/status', 'GET', '查询黑名单状态', '黑名单模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/app/user/block/status' AND `method` = 'GET');

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app/user/block/list', 'GET', '我的黑名单列表', '黑名单模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/app/user/block/list' AND `method` = 'GET');

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app/complaint/create', 'POST', '提交用户投诉', '投诉管理模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/app/complaint/create' AND `method` = 'POST');

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/complaint/list', 'GET', '查看投诉列表', '投诉管理模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/complaint/list' AND `method` = 'GET');

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/complaint/detail', 'GET', '查看投诉详情', '投诉管理模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/complaint/detail' AND `method` = 'GET');

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/complaint/handle', 'PUT', '处理投诉', '投诉管理模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/complaint/handle' AND `method` = 'PUT');

        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '投诉管理', NULL, 'menu', 'material-symbols:report-outline-rounded', 'complaint', 10, p.`id`, 0, '/operation/complaint', 0, NULL
        FROM `menu` p
        WHERE p.`path` = '/operation' AND p.`parent_id` = 0
          AND NOT EXISTS (
              SELECT 1 FROM `menu` m WHERE m.`path` = 'complaint' AND m.`parent_id` = p.`id`
          );

        INSERT IGNORE INTO `role_menu` (`role_id`, `menu_id`)
        SELECT r.`id`, m.`id`
        FROM `role` r
        JOIN `menu` m ON m.`path` = 'complaint' AND m.`component` = '/operation/complaint';

        INSERT IGNORE INTO `role_api` (`role_id`, `api_id`)
        SELECT r.`id`, a.`id`
        FROM `role` r
        JOIN `api` a ON (
            (a.`path` = '/api/v1/app/user/block' AND a.`method` IN ('POST', 'DELETE'))
            OR (a.`path` = '/api/v1/app/user/block/status' AND a.`method` = 'GET')
            OR (a.`path` = '/api/v1/app/user/block/list' AND a.`method` = 'GET')
            OR (a.`path` = '/api/v1/app/complaint/create' AND a.`method` = 'POST')
            OR (a.`path` = '/api/v1/complaint/list' AND a.`method` = 'GET')
            OR (a.`path` = '/api/v1/complaint/detail' AND a.`method` = 'GET')
            OR (a.`path` = '/api/v1/complaint/handle' AND a.`method` = 'PUT')
        );
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `role_menu`
        WHERE `menu_id` IN (
            SELECT `id` FROM `menu` WHERE `path` = 'complaint' AND `component` = '/operation/complaint'
        );

        DELETE FROM `role_api`
        WHERE `api_id` IN (
            SELECT `id` FROM `api`
            WHERE `path` IN (
                '/api/v1/app/user/block',
                '/api/v1/app/user/block/status',
                '/api/v1/app/user/block/list',
                '/api/v1/app/complaint/create',
                '/api/v1/complaint/list',
                '/api/v1/complaint/detail',
                '/api/v1/complaint/handle'
            )
        );

        DELETE FROM `api`
        WHERE `path` IN (
            '/api/v1/app/user/block',
            '/api/v1/app/user/block/status',
            '/api/v1/app/user/block/list',
            '/api/v1/app/complaint/create',
            '/api/v1/complaint/list',
            '/api/v1/complaint/detail',
            '/api/v1/complaint/handle'
        );

        DELETE FROM `menu`
        WHERE `path` = 'complaint' AND `component` = '/operation/complaint';

        DROP TABLE `user_complaint`;
        DROP TABLE `user_block`;
    """
