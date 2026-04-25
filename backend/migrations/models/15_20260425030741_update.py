from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE TABLE IF NOT EXISTS `moments` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL  DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL  DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `user_id` BIGINT NOT NULL  COMMENT '用户ID',
    `content` VARCHAR(500)   COMMENT '文本内容，500字以内',
    KEY `idx_moments_created_f30741` (`created_at`),
    KEY `idx_moments_updated_b763d4` (`updated_at`),
    KEY `idx_moments_user_id_497d48` (`user_id`)
) CHARACTER SET utf8mb4 COMMENT='用户动态';
        CREATE TABLE IF NOT EXISTS `moment_media` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `url` VARCHAR(500) NOT NULL  COMMENT '媒体URL',
    `media_type` INT NOT NULL  COMMENT '1=图片, 2=视频',
    `sort_order` INT NOT NULL  DEFAULT 0 COMMENT '排序序号',
    `cover_url` VARCHAR(500)   COMMENT '视频封面URL',
    `duration` INT   COMMENT '视频时长（秒）',
    `moment_id` BIGINT  COMMENT '所属动态ID'
) CHARACTER SET utf8mb4 COMMENT='动态媒体（图片/视频）';"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DROP TABLE IF EXISTS `moments`;
        DROP TABLE IF EXISTS `moment_media`;"""
