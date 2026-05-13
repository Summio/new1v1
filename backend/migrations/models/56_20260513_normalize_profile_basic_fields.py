from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        UPDATE `app_user`
        SET `birth_date` = NULL
        WHERE `birth_date` IS NOT NULL
          AND (`birth_date` < '1975-01-01' OR `birth_date` > CURRENT_DATE);

        UPDATE `app_user`
        SET `height_cm` = NULL
        WHERE `height_cm` IS NOT NULL
          AND (`height_cm` < 130 OR `height_cm` > 230);

        UPDATE `app_user`
        SET `weight_kg` = NULL
        WHERE `weight_kg` IS NOT NULL
          AND (`weight_kg` < 30 OR `weight_kg` > 130);
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return "SELECT 1;"
