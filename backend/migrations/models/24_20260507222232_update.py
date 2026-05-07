from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user` MODIFY COLUMN `coins` DECIMAL(18,2) NOT NULL  COMMENT '金币余额' DEFAULT 0;
        ALTER TABLE `app_user` MODIFY COLUMN `coins` DECIMAL(18,2) NOT NULL  COMMENT '金币余额' DEFAULT 0;
        ALTER TABLE `app_user` MODIFY COLUMN `coins` DECIMAL(18,2) NOT NULL  COMMENT '金币余额' DEFAULT 0;
        ALTER TABLE `app_user` MODIFY COLUMN `frozen_diamonds` DECIMAL(18,2) NOT NULL  COMMENT '冻结钻石' DEFAULT 0;
        ALTER TABLE `app_user` MODIFY COLUMN `frozen_diamonds` DECIMAL(18,2) NOT NULL  COMMENT '冻结钻石' DEFAULT 0;
        ALTER TABLE `app_user` MODIFY COLUMN `frozen_diamonds` DECIMAL(18,2) NOT NULL  COMMENT '冻结钻石' DEFAULT 0;
        ALTER TABLE `app_user` MODIFY COLUMN `diamonds` DECIMAL(18,2) NOT NULL  COMMENT '钻石余额' DEFAULT 0;
        ALTER TABLE `app_user` MODIFY COLUMN `diamonds` DECIMAL(18,2) NOT NULL  COMMENT '钻石余额' DEFAULT 0;
        ALTER TABLE `app_user` MODIFY COLUMN `diamonds` DECIMAL(18,2) NOT NULL  COMMENT '钻石余额' DEFAULT 0;
        ALTER TABLE `call_record` MODIFY COLUMN `anchor_income_diamonds` BIGINT NOT NULL  COMMENT '本次通话主播收益钻石' DEFAULT 0;
        ALTER TABLE `gift_record` MODIFY COLUMN `anchor_income_diamonds` DECIMAL(18,2) NOT NULL  COMMENT '主播礼物收益钻石' DEFAULT 0;
        ALTER TABLE `gift_record` MODIFY COLUMN `anchor_income_diamonds` DECIMAL(18,2) NOT NULL  COMMENT '主播礼物收益钻石' DEFAULT 0;
        ALTER TABLE `gift_record` MODIFY COLUMN `anchor_income_diamonds` DECIMAL(18,2) NOT NULL  COMMENT '主播礼物收益钻石' DEFAULT 0;"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user` MODIFY COLUMN `coins` BIGINT NOT NULL  COMMENT '金币余额(分)' DEFAULT 0;
        ALTER TABLE `app_user` MODIFY COLUMN `coins` BIGINT NOT NULL  COMMENT '金币余额(分)' DEFAULT 0;
        ALTER TABLE `app_user` MODIFY COLUMN `frozen_diamonds` BIGINT NOT NULL  COMMENT '冻结钻石(分)' DEFAULT 0;
        ALTER TABLE `app_user` MODIFY COLUMN `frozen_diamonds` BIGINT NOT NULL  COMMENT '冻结钻石(分)' DEFAULT 0;
        ALTER TABLE `app_user` MODIFY COLUMN `diamonds` BIGINT NOT NULL  COMMENT '钻石余额(分)' DEFAULT 0;
        ALTER TABLE `app_user` MODIFY COLUMN `diamonds` BIGINT NOT NULL  COMMENT '钻石余额(分)' DEFAULT 0;
        ALTER TABLE `call_record` MODIFY COLUMN `anchor_income_diamonds` BIGINT NOT NULL  COMMENT '本次通话主播收益钻石(分)' DEFAULT 0;
        ALTER TABLE `gift_record` MODIFY COLUMN `anchor_income_diamonds` BIGINT NOT NULL  COMMENT '主播礼物收益钻石(分)' DEFAULT 0;
        ALTER TABLE `gift_record` MODIFY COLUMN `anchor_income_diamonds` BIGINT NOT NULL  COMMENT '主播礼物收益钻石(分)' DEFAULT 0;"""
