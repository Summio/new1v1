from tortoise import BaseDBAsyncClient


RUN_IN_TRANSACTION = False


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        ALTER TABLE `aerich` ENGINE=InnoDB;
        ALTER TABLE `api` ENGINE=InnoDB;
        ALTER TABLE `app_user` ENGINE=InnoDB;
        ALTER TABLE `auditlog` ENGINE=InnoDB;
        ALTER TABLE `call_record` ENGINE=InnoDB;
        ALTER TABLE `dept` ENGINE=InnoDB;
        ALTER TABLE `deptclosure` ENGINE=InnoDB;
        ALTER TABLE `gift` ENGINE=InnoDB;
        ALTER TABLE `gift_record` ENGINE=InnoDB;
        ALTER TABLE `menu` ENGINE=InnoDB;
        ALTER TABLE `moment_media` ENGINE=InnoDB;
        ALTER TABLE `moments` ENGINE=InnoDB;
        ALTER TABLE `recharge_order` ENGINE=InnoDB;
        ALTER TABLE `role` ENGINE=InnoDB;
        ALTER TABLE `role_api` ENGINE=InnoDB;
        ALTER TABLE `role_menu` ENGINE=InnoDB;
        ALTER TABLE `system_config` ENGINE=InnoDB;
        ALTER TABLE `user` ENGINE=InnoDB;
        ALTER TABLE `user_role` ENGINE=InnoDB;
        ALTER TABLE `withdraw_apply` ENGINE=InnoDB;"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        """
