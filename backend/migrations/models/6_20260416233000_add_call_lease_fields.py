from tortoise import BaseDBAsyncClient

RUN_IN_TRANSACTION = True


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `call_record` ADD `connected_at` DATETIME(6) COMMENT '实际接通时间';
        ALTER TABLE `call_record` ADD `ended_at` DATETIME(6) COMMENT '结束时间';
        ALTER TABLE `call_record` ADD `deducted_amount` INT NOT NULL COMMENT '已扣费总额(分)' DEFAULT 0;
        ALTER TABLE `call_record` ADD `deducted_minutes` INT NOT NULL COMMENT '已扣费分钟数' DEFAULT 0;
        ALTER TABLE `call_record` ADD `last_renew_at` DATETIME(6) COMMENT '最后一次续租时间';
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `call_record` DROP COLUMN `last_renew_at`;
        ALTER TABLE `call_record` DROP COLUMN `deducted_minutes`;
        ALTER TABLE `call_record` DROP COLUMN `deducted_amount`;
        ALTER TABLE `call_record` DROP COLUMN `ended_at`;
        ALTER TABLE `call_record` DROP COLUMN `connected_at`;
    """


MODELS_STATE = ""
