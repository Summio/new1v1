from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user` ADD `location_city` VARCHAR(50)   COMMENT '所在地(省-市)';
        ALTER TABLE `app_user` ADD `album_photos` JSON   COMMENT '相册URL列表(最多6张)';
        ALTER TABLE `app_user` ADD `height_cm` INT   COMMENT '身高(cm)';
        ALTER TABLE `app_user` ADD `birth_date` DATE   COMMENT '出生日期';
        ALTER TABLE `app_user` ADD `cover_url` VARCHAR(500)   COMMENT '封面URL(必须来自相册)';
        ALTER TABLE `app_user` ADD `weight_kg` INT   COMMENT '体重(kg)';"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user` DROP COLUMN `location_city`;
        ALTER TABLE `app_user` DROP COLUMN `album_photos`;
        ALTER TABLE `app_user` DROP COLUMN `height_cm`;
        ALTER TABLE `app_user` DROP COLUMN `birth_date`;
        ALTER TABLE `app_user` DROP COLUMN `cover_url`;
        ALTER TABLE `app_user` DROP COLUMN `weight_kg`;"""
