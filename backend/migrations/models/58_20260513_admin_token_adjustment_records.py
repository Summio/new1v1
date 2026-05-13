from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE TABLE IF NOT EXISTS `app_user_token_adjust_record` (
            `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
            `app_user_id` BIGINT NOT NULL COMMENT '被调整的App用户ID',
            `operator_user_id` BIGINT NOT NULL COMMENT '后台操作人用户ID',
            `operator_username` VARCHAR(64) NOT NULL DEFAULT '' COMMENT '后台操作人用户名快照',
            `asset_type` VARCHAR(20) NOT NULL COMMENT '资产类型 coins/diamonds',
            `action` VARCHAR(20) NOT NULL COMMENT '调整方向 increase/decrease',
            `amount` DECIMAL(18,2) NOT NULL COMMENT '调整数量',
            `before_amount` DECIMAL(18,2) NOT NULL COMMENT '调整前余额',
            `after_amount` DECIMAL(18,2) NOT NULL COMMENT '调整后余额',
            `reason` VARCHAR(500) NOT NULL COMMENT '操作原因',
            `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) COMMENT '创建时间',
            `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6) COMMENT '更新时间',
            KEY `idx_token_adjust_app_user_id` (`app_user_id`),
            KEY `idx_token_adjust_operator_user_id` (`operator_user_id`),
            KEY `idx_token_adjust_asset_type` (`asset_type`),
            KEY `idx_token_adjust_action` (`action`),
            KEY `idx_token_adjust_created_at` (`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='后台代币调整审计记录';
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DROP TABLE IF EXISTS `app_user_token_adjust_record`;
    """
