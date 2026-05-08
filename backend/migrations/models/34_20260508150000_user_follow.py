from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE TABLE IF NOT EXISTS `user_follow` (
            `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
            `created_at` DATETIME(6) NOT NULL COMMENT '创建时间',
            `updated_at` DATETIME(6) NOT NULL COMMENT '更新时间',
            `follower_id` BIGINT NOT NULL COMMENT '关注者用户ID',
            `following_id` BIGINT NOT NULL COMMENT '被关注用户ID',
            UNIQUE KEY `uidx_user_follow_pair` (`follower_id`, `following_id`),
            KEY `idx_user_follow_follower` (`follower_id`),
            KEY `idx_user_follow_following` (`following_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户关注关系';
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DROP TABLE IF EXISTS `user_follow`;
    """
