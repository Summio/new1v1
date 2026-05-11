from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user`
            ADD COLUMN `text_dnd_enabled` BOOL NOT NULL DEFAULT 0 COMMENT '文字勿扰开关',
            ADD COLUMN `video_dnd_enabled` BOOL NOT NULL DEFAULT 0 COMMENT '视频勿扰开关',
            ADD COLUMN `ranking_invisible_enabled` BOOL NOT NULL DEFAULT 0 COMMENT '榜单隐身开关';
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user`
            DROP COLUMN `text_dnd_enabled`,
            DROP COLUMN `video_dnd_enabled`,
            DROP COLUMN `ranking_invisible_enabled`;
    """
