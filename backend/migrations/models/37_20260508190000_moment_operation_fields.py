from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `moments` ADD `is_pinned` BOOL NOT NULL DEFAULT 0 COMMENT '是否置顶';
        ALTER TABLE `moments` ADD `pinned_at` DATETIME(6) NULL COMMENT '置顶时间';
        ALTER TABLE `moments` ADD `recommend_override` BOOL NULL COMMENT '单条推荐覆盖值';
        CREATE INDEX `idx_moments_is_pinned` ON `moments` (`is_pinned`);
        CREATE INDEX `idx_moments_pinned_at` ON `moments` (`pinned_at`);
        CREATE INDEX `idx_moments_reco_override` ON `moments` (`recommend_override`);
        CREATE INDEX `idx_moments_feed_order` ON `moments` (`is_pinned`, `pinned_at`, `created_at`, `id`);
        CREATE INDEX `idx_moments_user_created` ON `moments` (`user_id`, `created_at`);
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DROP INDEX `idx_moments_user_created` ON `moments`;
        DROP INDEX `idx_moments_feed_order` ON `moments`;
        DROP INDEX `idx_moments_reco_override` ON `moments`;
        DROP INDEX `idx_moments_pinned_at` ON `moments`;
        DROP INDEX `idx_moments_is_pinned` ON `moments`;
        ALTER TABLE `moments` DROP COLUMN `recommend_override`;
        ALTER TABLE `moments` DROP COLUMN `pinned_at`;
        ALTER TABLE `moments` DROP COLUMN `is_pinned`;
    """
