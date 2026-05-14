from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE TABLE `system_popup_task` (
            `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
            `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '创建时间',
            `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '更新时间',
            `title` VARCHAR(50) NOT NULL COMMENT '弹窗标题',
            `content` TEXT NOT NULL COMMENT '弹窗正文，纯文本',
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
            KEY `idx_spt_type` (`type`),
            KEY `idx_spt_status_next` (`status`, `next_run_at`),
            KEY `idx_spt_send_mode` (`send_mode`),
            KEY `idx_spt_target_mode` (`target_mode`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='在线弹窗任务';

        CREATE TABLE `system_popup` (
            `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
            `task_id` BIGINT COMMENT '后台弹窗任务ID',
            `title` VARCHAR(50) NOT NULL COMMENT '弹窗标题',
            `content` TEXT NOT NULL COMMENT '弹窗正文，纯文本',
            `type` VARCHAR(20) NOT NULL COMMENT 'announcement/account/review/interaction',
            `publish_at` DATETIME(6) COMMENT '计划发布时间',
            `published_at` DATETIME(6) COMMENT '实际发布时间',
            `scheduled_run_at` DATETIME(6) COMMENT '调度批次时间',
            `run_key` VARCHAR(120) UNIQUE COMMENT '调度批次幂等键',
            `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '创建时间',
            PRIMARY KEY (`id`),
            UNIQUE KEY `system_popup_task_scheduled_run` (`task_id`, `scheduled_run_at`),
            KEY `idx_sp_type` (`type`),
            KEY `idx_sp_task` (`task_id`),
            KEY `idx_sp_published` (`published_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='在线弹窗实例';

        CREATE TABLE `system_popup_receipt` (
            `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键',
            `popup_id` BIGINT NOT NULL COMMENT '弹窗实例ID',
            `user_id` BIGINT NOT NULL COMMENT 'App用户ID',
            `pushed_at` DATETIME(6) COMMENT '推送时间',
            `ack_at` DATETIME(6) COMMENT '确认时间',
            `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '创建时间',
            PRIMARY KEY (`id`),
            UNIQUE KEY `system_popup_receipt_user` (`popup_id`, `user_id`),
            KEY `idx_spr_user_ack` (`user_id`, `ack_at`),
            KEY `idx_spr_popup` (`popup_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='在线弹窗推送确认回执';

        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '运营', NULL, 'catalog', 'material-symbols:monitoring-rounded', '/operation', 1, 0, 0, 'Layout', 0, '/operation/app-user'
        WHERE NOT EXISTS (
            SELECT 1 FROM `menu` WHERE `path` = '/operation' AND `parent_id` = 0
        );

        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '弹窗提示', NULL, 'menu', 'material-symbols:dialogs-outline-rounded', 'popup', 7, p.`id`, 0, '/operation/popup', 0, NULL
        FROM `menu` p
        WHERE p.`path` = '/operation' AND p.`parent_id` = 0
          AND NOT EXISTS (
              SELECT 1 FROM `menu` m WHERE m.`path` = 'popup' AND m.`parent_id` = p.`id`
          );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/popup/list', 'GET', '弹窗提示任务列表', '弹窗提示模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/popup/list' AND `method` = 'GET');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/popup/get', 'GET', '弹窗提示任务详情', '弹窗提示模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/popup/get' AND `method` = 'GET');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/popup/estimate-target-count', 'POST', '预计当前在线可触达人数', '弹窗提示模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/popup/estimate-target-count' AND `method` = 'POST');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/popup/create', 'POST', '创建弹窗提示任务', '弹窗提示模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/popup/create' AND `method` = 'POST');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/popup/update', 'POST', '更新弹窗提示任务', '弹窗提示模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/popup/update' AND `method` = 'POST');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/popup/publish', 'POST', '发布弹窗提示任务', '弹窗提示模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/popup/publish' AND `method` = 'POST');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/popup/pause', 'POST', '暂停弹窗提示任务', '弹窗提示模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/popup/pause' AND `method` = 'POST');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/popup/resume', 'POST', '恢复弹窗提示任务', '弹窗提示模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/popup/resume' AND `method` = 'POST');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/popup/cancel', 'POST', '取消弹窗提示任务', '弹窗提示模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/popup/cancel' AND `method` = 'POST');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/popup/delete', 'DELETE', '删除弹窗提示任务', '弹窗提示模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/popup/delete' AND `method` = 'DELETE');
        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app/popups/{popup_id}/ack', 'POST', '确认在线弹窗', '弹窗提示模块'
        WHERE NOT EXISTS (SELECT 1 FROM `api` WHERE `path` = '/api/v1/app/popups/{popup_id}/ack' AND `method` = 'POST');

        INSERT IGNORE INTO `role_menu` (`role_id`, `menu_id`)
        SELECT r.`id`, m.`id`
        FROM `role` r
        JOIN `menu` m ON (
            (m.`path` = '/operation' AND m.`parent_id` = 0)
            OR (m.`path` = 'popup' AND m.`component` = '/operation/popup')
        );

        INSERT IGNORE INTO `role_api` (`role_id`, `api_id`)
        SELECT r.`id`, a.`id`
        FROM `role` r
        JOIN `api` a ON a.`tags` = '弹窗提示模块';
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `role_menu`
        WHERE `menu_id` IN (
            SELECT `id` FROM `menu` WHERE `path` = 'popup' AND `component` = '/operation/popup'
        );
        DELETE FROM `role_api`
        WHERE `api_id` IN (SELECT `id` FROM `api` WHERE `tags` = '弹窗提示模块');
        DELETE FROM `api` WHERE `tags` = '弹窗提示模块';
        DELETE FROM `menu` WHERE `path` = 'popup' AND `component` = '/operation/popup';
        DROP TABLE IF EXISTS `system_popup_receipt`;
        DROP TABLE IF EXISTS `system_popup`;
        DROP TABLE IF EXISTS `system_popup_task`;
    """
