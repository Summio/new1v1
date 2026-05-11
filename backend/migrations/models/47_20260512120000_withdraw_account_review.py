from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `withdraw_account` ADD `status` VARCHAR(20) NOT NULL DEFAULT 'pending' COMMENT '审核状态';
        ALTER TABLE `withdraw_account` ADD `reviewed_by` BIGINT COMMENT '审核人后台用户ID';
        ALTER TABLE `withdraw_account` ADD `reviewed_at` DATETIME(6) COMMENT '审核时间';
        ALTER TABLE `withdraw_account` ADD `review_remark` VARCHAR(500) COMMENT '审核备注/驳回原因';
        CREATE INDEX `idx_withdraw_ac_status_review` ON `withdraw_account` (`status`);
        UPDATE `withdraw_account` SET `status` = 'approved' WHERE `status` = 'pending';

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/withdraw/account/list', 'GET', '提现账户审核列表', '提现模块'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/withdraw/account/list' AND `method` = 'GET'
        );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/withdraw/account/review', 'POST', '审核提现账户', '提现模块'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/withdraw/account/review' AND `method` = 'POST'
        );

        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '提现账户审核', NULL, 'menu', 'material-symbols:fact-check-outline-rounded', 'withdraw-account', 7, p.`id`, 0, '/operation/withdraw-account', 0, NULL
        FROM `menu` p
        WHERE p.`path` = '/operation' AND p.`parent_id` = 0
          AND NOT EXISTS (
              SELECT 1 FROM `menu` m WHERE m.`path` = 'withdraw-account' AND m.`parent_id` = p.`id`
          );

        INSERT IGNORE INTO `role_menu` (`role_id`, `menu_id`)
        SELECT r.`id`, m.`id`
        FROM `role` r
        JOIN `menu` m ON m.`path` = 'withdraw-account' AND m.`component` = '/operation/withdraw-account';

        INSERT IGNORE INTO `role_api` (`role_id`, `api_id`)
        SELECT r.`id`, a.`id`
        FROM `role` r
        JOIN `api` a ON (
            (a.`path` = '/api/v1/withdraw/account/list' AND a.`method` = 'GET')
            OR (a.`path` = '/api/v1/withdraw/account/review' AND a.`method` = 'POST')
        );
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `role_menu`
        WHERE `menu_id` IN (
            SELECT `id` FROM `menu` WHERE `path` = 'withdraw-account' AND `component` = '/operation/withdraw-account'
        );

        DELETE FROM `role_api`
        WHERE `api_id` IN (
            SELECT `id` FROM `api`
            WHERE (`path` = '/api/v1/withdraw/account/list' AND `method` = 'GET')
               OR (`path` = '/api/v1/withdraw/account/review' AND `method` = 'POST')
        );

        DELETE FROM `api`
        WHERE (`path` = '/api/v1/withdraw/account/list' AND `method` = 'GET')
           OR (`path` = '/api/v1/withdraw/account/review' AND `method` = 'POST');

        DELETE FROM `menu`
        WHERE `path` = 'withdraw-account' AND `component` = '/operation/withdraw-account';

        DROP INDEX `idx_withdraw_ac_status_review` ON `withdraw_account`;
        ALTER TABLE `withdraw_account` DROP COLUMN `review_remark`;
        ALTER TABLE `withdraw_account` DROP COLUMN `reviewed_at`;
        ALTER TABLE `withdraw_account` DROP COLUMN `reviewed_by`;
        ALTER TABLE `withdraw_account` DROP COLUMN `status`;
    """
