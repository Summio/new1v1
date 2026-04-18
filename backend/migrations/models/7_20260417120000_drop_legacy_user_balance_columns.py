from tortoise import BaseDBAsyncClient

RUN_IN_TRANSACTION = True


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user` DROP COLUMN `frozen_balance`;
        ALTER TABLE `app_user` DROP COLUMN `balance`;
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user` ADD `balance` INT NOT NULL COMMENT '钱包余额(分)' DEFAULT 0;
        ALTER TABLE `app_user` ADD `frozen_balance` INT NOT NULL COMMENT '冻结余额(分)' DEFAULT 0;
        ALTER TABLE `app_user` ADD INDEX `idx_app_user_frozen__90cda7` (`frozen_balance`);
    """


MODELS_STATE = ""
