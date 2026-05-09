from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        UPDATE `app_user`
        SET `gender` = 'male'
        WHERE `gender` IS NULL
           OR `gender` = ''
           OR `gender` NOT IN ('male', 'female');
        ALTER TABLE `app_user`
            MODIFY COLUMN `gender` VARCHAR(10) NULL COMMENT 'male/female' DEFAULT 'male';
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user`
            MODIFY COLUMN `gender` VARCHAR(10) NULL COMMENT 'male/female/secret' DEFAULT 'secret';
    """
