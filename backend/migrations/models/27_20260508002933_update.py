from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE TABLE IF NOT EXISTS `withdraw_account` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL  DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL  DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `user_id` BIGINT NOT NULL UNIQUE COMMENT '用户ID',
    `real_name` VARCHAR(30) NOT NULL  COMMENT '真实姓名',
    `account_no` VARCHAR(80) NOT NULL  COMMENT '支付宝账号',
    `payment_qr_code` VARCHAR(500) NOT NULL  COMMENT '收款码URL',
    KEY `idx_withdraw_ac_created_c267c7` (`created_at`),
    KEY `idx_withdraw_ac_updated_082ddf` (`updated_at`),
    KEY `idx_withdraw_ac_user_id_f1ed3d` (`user_id`)
) CHARACTER SET utf8mb4 COMMENT='用户提现账户';
        ALTER TABLE `withdraw_apply` ADD `payment_qr_code` VARCHAR(500)   COMMENT '收款码URL';"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `withdraw_apply` DROP COLUMN `payment_qr_code`;
        DROP TABLE IF EXISTS `withdraw_account`;"""
