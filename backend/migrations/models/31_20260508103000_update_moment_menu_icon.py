from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        UPDATE `menu`
        SET `icon` = 'material-symbols:dynamic-feed-rounded'
        WHERE `path` = 'moment' AND `component` = '/operation/moment';"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        UPDATE `menu`
        SET `icon` = 'material-symbols:dynamic-feed-outline-rounded'
        WHERE `path` = 'moment' AND `component` = '/operation/moment';"""
