from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user` MODIFY COLUMN `diamonds` BIGINT NOT NULL  COMMENT '钻石余额(分)' DEFAULT 0;
        ALTER TABLE `app_user` MODIFY COLUMN `coins` BIGINT NOT NULL  COMMENT '金币余额(分)' DEFAULT 0;
        ALTER TABLE `app_user` MODIFY COLUMN `frozen_diamonds` BIGINT NOT NULL  COMMENT '冻结钻石(分)' DEFAULT 0;
        ALTER TABLE `call_record` MODIFY COLUMN `call_price` BIGINT NOT NULL  COMMENT '通话单价(分/分钟)，以发起时价格固定计费' DEFAULT 0;
        ALTER TABLE `call_record` MODIFY COLUMN `total_fee` BIGINT NOT NULL  COMMENT '总费用(分)' DEFAULT 0;
        ALTER TABLE `call_record` MODIFY COLUMN `deducted_amount` BIGINT NOT NULL  COMMENT '已扣费总额(分)' DEFAULT 0;
        ALTER TABLE `gift_record` MODIFY COLUMN `price` BIGINT NOT NULL  COMMENT '价格(分)';
        ALTER TABLE `recharge_order` MODIFY COLUMN `amount` BIGINT NOT NULL  COMMENT '充值金额(分)';
        ALTER TABLE `withdraw_apply` MODIFY COLUMN `amount` BIGINT NOT NULL  COMMENT '提现金额(分)';"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `app_user` MODIFY COLUMN `diamonds` INT NOT NULL  COMMENT '钻石余额(分)' DEFAULT 0;
        ALTER TABLE `app_user` MODIFY COLUMN `coins` INT NOT NULL  COMMENT '金币余额(分)' DEFAULT 0;
        ALTER TABLE `app_user` MODIFY COLUMN `frozen_diamonds` INT NOT NULL  COMMENT '冻结钻石(分)' DEFAULT 0;
        ALTER TABLE `call_record` MODIFY COLUMN `call_price` INT NOT NULL  COMMENT '通话单价(分/分钟)，以发起时价格固定计费' DEFAULT 0;
        ALTER TABLE `call_record` MODIFY COLUMN `total_fee` INT NOT NULL  COMMENT '总费用(分)' DEFAULT 0;
        ALTER TABLE `call_record` MODIFY COLUMN `deducted_amount` INT NOT NULL  COMMENT '已扣费总额(分)' DEFAULT 0;
        ALTER TABLE `gift_record` MODIFY COLUMN `price` INT NOT NULL  COMMENT '价格(分)';
        ALTER TABLE `recharge_order` MODIFY COLUMN `amount` INT NOT NULL  COMMENT '充值金额(分)';
        ALTER TABLE `withdraw_apply` MODIFY COLUMN `amount` INT NOT NULL  COMMENT '提现金额(分)';"""
