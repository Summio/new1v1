from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `gift_record` ADD `total_price` BIGINT NOT NULL  COMMENT '礼物总价(分)' DEFAULT 0;
        ALTER TABLE `gift_record` ADD `quantity` INT NOT NULL  COMMENT '礼物数量' DEFAULT 1;
        ALTER TABLE `gift_record` ADD `anchor_share_bps` INT NOT NULL  COMMENT '主播分成比例快照(万分比)' DEFAULT 10000;
        ALTER TABLE `gift_record` ADD `anchor_income_diamonds` BIGINT NOT NULL  COMMENT '主播礼物收益钻石(分)' DEFAULT 0;
        ALTER TABLE `gift_record` MODIFY COLUMN `price` BIGINT NOT NULL  COMMENT '礼物单价(分)';"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `gift_record` DROP COLUMN `total_price`;
        ALTER TABLE `gift_record` DROP COLUMN `quantity`;
        ALTER TABLE `gift_record` DROP COLUMN `anchor_share_bps`;
        ALTER TABLE `gift_record` DROP COLUMN `anchor_income_diamonds`;
        ALTER TABLE `gift_record` MODIFY COLUMN `price` BIGINT NOT NULL  COMMENT '价格(分)';"""
