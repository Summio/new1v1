from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE TABLE IF NOT EXISTS `im_text_message_charge_record` (
            `id` INT NOT NULL PRIMARY KEY AUTO_INCREMENT,
            `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
            `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
            `sender_id` BIGINT NOT NULL,
            `receiver_id` BIGINT NOT NULL,
            `request_id` VARCHAR(64) NOT NULL,
            `price` BIGINT NOT NULL DEFAULT 0,
            `anchor_share_bps` INT NOT NULL DEFAULT 5000,
            `anchor_income_diamonds` BIGINT NOT NULL DEFAULT 0,
            `status` VARCHAR(20) NOT NULL DEFAULT 'charged',
            KEY `idx_im_text_sender` (`sender_id`),
            KEY `idx_im_text_receiver` (`receiver_id`),
            KEY `idx_im_text_status` (`status`),
            UNIQUE KEY `uid_im_text_sender_request` (`sender_id`, `request_id`)
        ) CHARACTER SET utf8mb4;

        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'im_text_message_billing_enabled', 'false', '文字聊天扣费开关', NOW(6), NOW(6)
        WHERE NOT EXISTS (SELECT 1 FROM `system_config` WHERE `cfg_key` = 'im_text_message_billing_enabled');

        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'im_text_message_price', '0', '文字聊天每条扣费金币数', NOW(6), NOW(6)
        WHERE NOT EXISTS (SELECT 1 FROM `system_config` WHERE `cfg_key` = 'im_text_message_price');

        INSERT INTO `system_config` (`cfg_key`, `cfg_value`, `description`, `created_at`, `updated_at`)
        SELECT 'im_text_message_anchor_share_bps', '5000', '文字聊天主播分成比例', NOW(6), NOW(6)
        WHERE NOT EXISTS (SELECT 1 FROM `system_config` WHERE `cfg_key` = 'im_text_message_anchor_share_bps');
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DROP TABLE IF EXISTS `im_text_message_charge_record`;
    """
