from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE TABLE IF NOT EXISTS `im_text_message_charge_record` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL  DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL  DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `sender_id` BIGINT NOT NULL  COMMENT '发送方用户ID',
    `receiver_id` BIGINT NOT NULL  COMMENT '接收方用户ID',
    `request_id` VARCHAR(64) NOT NULL  COMMENT '客户端请求幂等ID',
    `price` BIGINT NOT NULL  COMMENT '文字消息扣费金币数' DEFAULT 0,
    `anchor_share_bps` INT NOT NULL  COMMENT '主播分成比例快照(万分比)' DEFAULT 5000,
    `anchor_income_diamonds` BIGINT NOT NULL  COMMENT '主播收益钻石' DEFAULT 0,
    `status` VARCHAR(20) NOT NULL  COMMENT 'charged' DEFAULT 'charged',
    UNIQUE KEY `uid_im_text_mes_sender__f2af8c` (`sender_id`, `request_id`),
    KEY `idx_im_text_mes_created_fd1ae6` (`created_at`),
    KEY `idx_im_text_mes_updated_f1bf20` (`updated_at`),
    KEY `idx_im_text_mes_sender__a29093` (`sender_id`),
    KEY `idx_im_text_mes_receive_1b7be5` (`receiver_id`),
    KEY `idx_im_text_mes_status_4de307` (`status`)
) CHARACTER SET utf8mb4 COMMENT='IM 文字消息扣费记录';"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DROP TABLE IF EXISTS `im_text_message_charge_record`;"""
