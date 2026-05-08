from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user` ADD `is_recommended` BOOL NOT NULL DEFAULT 0 COMMENT '是否首页推荐主播';
        ALTER TABLE `app_user` ADD `recommend_weight` INT NOT NULL DEFAULT 0 COMMENT '主播推荐值';
        CREATE INDEX `idx_app_user_is_reco_5acb9a` ON `app_user` (`is_recommended`);
        CREATE INDEX `idx_app_user_recomme_1d7c5f` ON `app_user` (`recommend_weight`);"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DROP INDEX `idx_app_user_recomme_1d7c5f` ON `app_user`;
        DROP INDEX `idx_app_user_is_reco_5acb9a` ON `app_user`;
        ALTER TABLE `app_user` DROP COLUMN `recommend_weight`;
        ALTER TABLE `app_user` DROP COLUMN `is_recommended`;"""
