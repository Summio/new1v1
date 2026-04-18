from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `anchor` MODIFY COLUMN `call_price` BIGINT NOT NULL  COMMENT '每分钟通话价格(分)' DEFAULT 100;
        ALTER TABLE `call_record` MODIFY COLUMN `deducted_minutes` BIGINT NOT NULL  COMMENT '已扣费分钟数' DEFAULT 0;
        ALTER TABLE `gift` MODIFY COLUMN `price` BIGINT NOT NULL  COMMENT '价格(分)';"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `gift` MODIFY COLUMN `price` INT NOT NULL  COMMENT '价格(分)';
        ALTER TABLE `anchor` MODIFY COLUMN `call_price` INT NOT NULL  COMMENT '每分钟通话价格(分)' DEFAULT 100;
        ALTER TABLE `call_record` MODIFY COLUMN `deducted_minutes` INT NOT NULL  COMMENT '已扣费分钟数' DEFAULT 0;"""
