from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `im_text_message_charge_record` MODIFY COLUMN `anchor_income_diamonds` DECIMAL(18,2) NOT NULL  COMMENT '主播收益钻石' DEFAULT 0;
        ALTER TABLE `im_text_message_charge_record` MODIFY COLUMN `anchor_income_diamonds` DECIMAL(18,2) NOT NULL  COMMENT '主播收益钻石' DEFAULT 0;"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `im_text_message_charge_record` MODIFY COLUMN `anchor_income_diamonds` BIGINT NOT NULL  COMMENT '主播收益钻石' DEFAULT 0;"""
