from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        SET @col_exists := (
            SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND COLUMN_NAME = 'vip_expires_at'
        );
        SET @ddl := IF(
            @col_exists = 0,
            'ALTER TABLE `app_user` ADD COLUMN `vip_expires_at` DATETIME(6) NULL COMMENT ''VIP到期时间''',
            'SELECT 1'
        );
        PREPARE stmt FROM @ddl;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

        SET @idx_exists := (
            SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'app_user'
              AND INDEX_NAME = 'idx_app_user_vip_expires_at'
        );
        SET @idx_ddl := IF(
            @idx_exists = 0,
            'CREATE INDEX `idx_app_user_vip_expires_at` ON `app_user` (`vip_expires_at`)',
            'SELECT 1'
        );
        PREPARE idx_stmt FROM @idx_ddl;
        EXECUTE idx_stmt;
        DEALLOCATE PREPARE idx_stmt;

        CREATE TABLE IF NOT EXISTS `vip_order` (
            `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
            `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
            `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
            `user_id` BIGINT NOT NULL,
            `order_no` VARCHAR(64) NOT NULL UNIQUE,
            `amount` BIGINT NOT NULL COMMENT 'VIP金额(分)',
            `duration_days` INT NOT NULL,
            `package_snapshot` JSON NULL,
            `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
            `pay_channel` VARCHAR(20) NULL,
            `paid_at` DATETIME(6) NULL,
            `before_vip_expires_at` DATETIME(6) NULL,
            `after_vip_expires_at` DATETIME(6) NULL,
            INDEX `idx_vip_order_user_id` (`user_id`),
            INDEX `idx_vip_order_status` (`status`),
            INDEX `idx_vip_order_order_no` (`order_no`)
        ) CHARACTER SET utf8mb4 COMMENT='VIP会员购买订单';

        INSERT INTO `system_config` (`created_at`, `updated_at`, `cfg_key`, `cfg_value`, `description`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), 'vip_packages',
               '[{"amount":1990,"duration_days":30,"label":"月卡","tag":"推荐","tag_color":"#D7A84F"},{"amount":5800,"duration_days":90,"label":"季卡","tag":"省心","tag_color":"#C7902D"},{"amount":19800,"duration_days":365,"label":"年卡","tag":"超值","tag_color":"#B7791F"}]',
               'VIP套餐配置'
        WHERE NOT EXISTS (
            SELECT 1 FROM `system_config` WHERE `cfg_key` = 'vip_packages'
        );

        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '设置', NULL, 'catalog', 'material-symbols:tune-rounded', '/settings', 4, 0, 0, 'Layout', 0, '/settings/recharge-config'
        WHERE NOT EXISTS (
            SELECT 1 FROM `menu` WHERE `path` = '/settings' AND `parent_id` = 0
        );

        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), 'VIP配置', NULL, 'menu', 'material-symbols:workspace-premium-outline-rounded', 'vip-config', 5, p.`id`, 0, '/system/vip-config', 0, NULL
        FROM `menu` p
        WHERE p.`path` = '/settings' AND p.`parent_id` = 0
          AND NOT EXISTS (
              SELECT 1 FROM `menu` m WHERE m.`path` = 'vip-config' AND m.`parent_id` = p.`id`
          );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/apis/system/vip-config', 'GET', '获取VIP配置', '系统配置-VIP'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/apis/system/vip-config' AND `method` = 'GET'
        );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/apis/system/vip-config', 'PUT', '更新VIP配置', '系统配置-VIP'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/apis/system/vip-config' AND `method` = 'PUT'
        );

        INSERT IGNORE INTO `role_menu` (`role_id`, `menu_id`)
        SELECT r.`id`, m.`id`
        FROM `role` r
        JOIN `menu` m ON (
            (m.`path` = '/settings' AND m.`parent_id` = 0)
            OR (m.`path` = 'vip-config' AND m.`component` = '/system/vip-config')
        );

        INSERT IGNORE INTO `role_api` (`role_id`, `api_id`)
        SELECT r.`id`, a.`id`
        FROM `role` r
        JOIN `api` a ON a.`path` = '/api/v1/apis/system/vip-config' AND a.`method` IN ('GET', 'PUT');
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `role_menu`
        WHERE `menu_id` IN (
            SELECT `id` FROM `menu` WHERE `path` = 'vip-config' AND `component` = '/system/vip-config'
        );

        DELETE FROM `role_api`
        WHERE `api_id` IN (
            SELECT `id` FROM `api`
            WHERE `path` = '/api/v1/apis/system/vip-config' AND `method` IN ('GET', 'PUT')
        );

        DELETE FROM `api`
        WHERE `path` = '/api/v1/apis/system/vip-config' AND `method` IN ('GET', 'PUT');

        DELETE FROM `menu`
        WHERE `path` = 'vip-config' AND `component` = '/system/vip-config';

        DELETE FROM `system_config` WHERE `cfg_key` = 'vip_packages';
        DROP TABLE IF EXISTS `vip_order`;
        DROP INDEX `idx_app_user_vip_expires_at` ON `app_user`;
        ALTER TABLE `app_user` DROP COLUMN `vip_expires_at`;
    """
