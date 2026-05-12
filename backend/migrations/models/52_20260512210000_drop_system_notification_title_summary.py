from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `system_notification_task` DROP COLUMN `title`;
        ALTER TABLE `system_notification_task` DROP COLUMN `summary`;
        ALTER TABLE `system_notification` DROP COLUMN `title`;
        ALTER TABLE `system_notification` DROP COLUMN `summary`;
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `system_notification_task` ADD COLUMN `title` VARCHAR(100) NOT NULL COMMENT '通知标题' DEFAULT '';
        ALTER TABLE `system_notification_task` ADD COLUMN `summary` VARCHAR(200) NOT NULL COMMENT '通知摘要' DEFAULT '';
        ALTER TABLE `system_notification` ADD COLUMN `title` VARCHAR(100) NOT NULL COMMENT '通知标题' DEFAULT '';
        ALTER TABLE `system_notification` ADD COLUMN `summary` VARCHAR(200) NOT NULL COMMENT '通知摘要' DEFAULT '';
    """
