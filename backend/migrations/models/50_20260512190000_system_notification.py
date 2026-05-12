from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE TABLE `system_notification_task` (
            `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
            `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '创建时间',
            `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '更新时间',
            `title` VARCHAR(100) NOT NULL COMMENT '通知标题',
            `summary` VARCHAR(200) NOT NULL COMMENT '通知摘要',
            `content` TEXT NOT NULL COMMENT '通知正文，纯文本',
            `type` VARCHAR(20) NOT NULL COMMENT 'announcement/account/review/interaction',
            `status` VARCHAR(20) NOT NULL DEFAULT 'draft' COMMENT 'draft/scheduled/running/paused/completed/cancelled',
            `send_mode` VARCHAR(20) NOT NULL DEFAULT 'immediate' COMMENT 'immediate/once/repeat',
            `target_mode` VARCHAR(20) NOT NULL DEFAULT 'all' COMMENT 'all/user_ids/filter',
            `target_user_ids` JSON COMMENT '指定用户ID列表',
            `target_filters` JSON COMMENT '筛选条件',
            `publish_at` DATETIME(6) COMMENT '一次性发布时间',
            `repeat_type` VARCHAR(20) COMMENT 'daily/weekly/monthly',
            `repeat_time` VARCHAR(5) COMMENT 'HH:mm',
            `repeat_weekday` INT COMMENT '周几 0-6',
            `repeat_month_day` INT COMMENT '每月几号 1-31',
            `start_at` DATETIME(6) COMMENT '周期开始时间',
            `end_at` DATETIME(6) COMMENT '周期结束时间',
            `max_runs` INT COMMENT '最大发送次数',
            `run_count` INT NOT NULL DEFAULT 0 COMMENT '已发送次数',
            `next_run_at` DATETIME(6) COMMENT '下次发送时间',
            `last_run_at` DATETIME(6) COMMENT '上次发送时间',
            `created_by` BIGINT COMMENT '创建后台用户ID',
            PRIMARY KEY (`id`),
            KEY `idx_snt_type` (`type`),
            KEY `idx_snt_status_next` (`status`, `next_run_at`),
            KEY `idx_snt_send_mode` (`send_mode`),
            KEY `idx_snt_target_mode` (`target_mode`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='系统通知任务';

        CREATE TABLE `system_notification` (
            `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
            `task_id` BIGINT COMMENT '后台通知任务ID',
            `title` VARCHAR(100) NOT NULL COMMENT '通知标题',
            `summary` VARCHAR(200) NOT NULL COMMENT '通知摘要',
            `content` TEXT NOT NULL COMMENT '通知正文，纯文本',
            `type` VARCHAR(20) NOT NULL COMMENT 'announcement/account/review/interaction',
            `source` VARCHAR(20) NOT NULL DEFAULT 'admin' COMMENT 'admin/system',
            `publish_at` DATETIME(6) COMMENT '计划发布时间',
            `published_at` DATETIME(6) COMMENT '实际发布时间',
            `scheduled_run_at` DATETIME(6) COMMENT '调度批次时间',
            `run_key` VARCHAR(120) UNIQUE COMMENT '调度批次幂等键',
            `biz_key` VARCHAR(160) UNIQUE COMMENT '业务幂等键',
            `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '创建时间',
            PRIMARY KEY (`id`),
            UNIQUE KEY `system_notification_task_scheduled_run` (`task_id`, `scheduled_run_at`),
            UNIQUE KEY `system_notification_biz_key` (`biz_key`),
            KEY `idx_sn_type` (`type`),
            KEY `idx_sn_task` (`task_id`),
            KEY `idx_sn_published` (`published_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='系统通知实例';

        CREATE TABLE `system_notification_receipt` (
            `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
            `notification_id` BIGINT NOT NULL COMMENT '通知实例ID',
            `user_id` BIGINT NOT NULL COMMENT 'App用户ID',
            `read_at` DATETIME(6) COMMENT '已读时间',
            `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '创建时间',
            PRIMARY KEY (`id`),
            UNIQUE KEY `system_notification_receipt_user` (`notification_id`, `user_id`),
            KEY `idx_snr_user_read` (`user_id`, `read_at`),
            KEY `idx_snr_notification` (`notification_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='系统通知回执';

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app/notifications', 'GET', '系统通知列表', '系统通知模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/app/notifications' AND `method` = 'GET');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app/notifications/unread-count', 'GET', '系统通知未读数', '系统通知模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/app/notifications/unread-count' AND `method` = 'GET');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/notification/estimate-target-count', 'POST', '预计系统通知触达人数', '系统通知模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/notification/estimate-target-count' AND `method` = 'POST');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/notification/list', 'GET', '系统通知任务列表', '系统通知模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/notification/list' AND `method` = 'GET');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/notification/create', 'POST', '创建系统通知任务', '系统通知模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/notification/create' AND `method` = 'POST');

        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '系统通知', NULL, 'menu', 'material-symbols:notifications-outline-rounded', 'system-notification', 12, p.`id`, 0, '/operation/system-notification', 0, NULL
        FROM `menu` p
        WHERE p.`path` = '/operation' AND p.`parent_id` = 0
          AND NOT EXISTS (
              SELECT 1 FROM `menu` m WHERE m.`path` = 'system-notification' AND m.`parent_id` = p.`id`
          );

        INSERT IGNORE INTO `role_menu` (`role_id`, `menu_id`)
        SELECT r.`id`, m.`id`
        FROM `role` r
        JOIN `menu` m ON m.`path` = 'system-notification' AND m.`component` = '/operation/system-notification';

        INSERT IGNORE INTO `role_api` (`role_id`, `api_id`)
        SELECT r.`id`, a.`id`
        FROM `role` r
        JOIN `api` a ON a.`tags` = '系统通知模块';
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `role_menu`
        WHERE `menu_id` IN (
            SELECT `id` FROM `menu` WHERE `path` = 'system-notification' AND `component` = '/operation/system-notification'
        );
        DELETE FROM `role_api`
        WHERE `api_id` IN (SELECT `id` FROM `api` WHERE `tags` = '系统通知模块');
        DELETE FROM `api` WHERE `tags` = '系统通知模块';
        DELETE FROM `menu` WHERE `path` = 'system-notification' AND `component` = '/operation/system-notification';
        DROP TABLE `system_notification_receipt`;
        DROP TABLE `system_notification`;
        DROP TABLE `system_notification_task`;
    """
