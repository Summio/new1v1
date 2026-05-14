from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE TABLE IF NOT EXISTS `app_user_common_phrase` (
            `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
            `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
            `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
            `user_id` BIGINT NOT NULL COMMENT 'App用户ID',
            `slot_index` INT NOT NULL COMMENT '槽位编号 1/2/3',
            `approved_content` VARCHAR(50) NOT NULL DEFAULT '' COMMENT '已审核通过内容',
            `pending_content` VARCHAR(50) NOT NULL DEFAULT '' COMMENT '待审核/被驳回内容',
            `review_status` VARCHAR(20) NOT NULL DEFAULT 'none' COMMENT 'none/pending/approved/rejected',
            `review_remark` VARCHAR(500) NOT NULL DEFAULT '' COMMENT '审核备注/驳回原因',
            `submitted_at` DATETIME(6) NULL COMMENT '提交时间',
            `reviewed_at` DATETIME(6) NULL COMMENT '审核时间',
            `reviewed_by` BIGINT NULL COMMENT '审核后台用户ID',
            UNIQUE KEY `uid_app_user_c_user_id_4d7f2a` (`user_id`, `slot_index`),
            KEY `idx_app_user_co_user_id_519a6f` (`user_id`),
            KEY `idx_app_user_co_slot_in_3afc4f` (`slot_index`),
            KEY `idx_app_user_co_review__07635a` (`review_status`)
        ) CHARACTER SET utf8mb4 COMMENT='真人认证用户常用语槽位';

        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '审核', NULL, 'catalog', 'material-symbols:fact-check-outline-rounded', '/review', 2, 0, 0, 'Layout', 0, '/review/certification-review'
        WHERE NOT EXISTS (
            SELECT 1 FROM `menu` WHERE `path` = '/review' AND `parent_id` = 0
        );

        INSERT INTO `menu` (`created_at`, `updated_at`, `name`, `remark`, `menu_type`, `icon`, `path`, `order`, `parent_id`, `is_hidden`, `component`, `keepalive`, `redirect`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '常用语审核', NULL, 'menu', 'material-symbols:chat-paste-go-outline-rounded', 'common-phrase-review', 6, p.`id`, 0, '/operation/common-phrase-review', 0, NULL
        FROM `menu` p
        WHERE p.`path` = '/review' AND p.`parent_id` = 0
          AND NOT EXISTS (
              SELECT 1 FROM `menu` m WHERE m.`path` = 'common-phrase-review' AND m.`parent_id` = p.`id`
          );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app_user/common-phrase-review/list', 'GET', '查看常用语审核列表', 'App用户模块'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/app_user/common-phrase-review/list' AND `method` = 'GET'
        );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app_user/common-phrase-review/get', 'GET', '查看常用语审核详情', 'App用户模块'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/app_user/common-phrase-review/get' AND `method` = 'GET'
        );

        INSERT INTO `api` (`created_at`, `updated_at`, `path`, `method`, `summary`, `tags`)
        SELECT CURRENT_TIMESTAMP(6), CURRENT_TIMESTAMP(6), '/api/v1/app_user/common-phrase-review/review', 'POST', '审核常用语', 'App用户模块'
        WHERE NOT EXISTS (
            SELECT 1 FROM `api` WHERE `path` = '/api/v1/app_user/common-phrase-review/review' AND `method` = 'POST'
        );

        INSERT IGNORE INTO `role_menu` (`role_id`, `menu_id`)
        SELECT r.`id`, m.`id`
        FROM `role` r
        JOIN `menu` m ON (
            (m.`path` = '/review' AND m.`parent_id` = 0)
            OR (m.`path` = 'common-phrase-review' AND m.`component` = '/operation/common-phrase-review')
        );

        INSERT IGNORE INTO `role_api` (`role_id`, `api_id`)
        SELECT r.`id`, a.`id`
        FROM `role` r
        JOIN `api` a ON a.`path` IN (
            '/api/v1/app_user/common-phrase-review/list',
            '/api/v1/app_user/common-phrase-review/get',
            '/api/v1/app_user/common-phrase-review/review'
        );
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DELETE FROM `role_menu`
        WHERE `menu_id` IN (
            SELECT `id` FROM `menu` WHERE `path` = 'common-phrase-review' AND `component` = '/operation/common-phrase-review'
        );

        DELETE FROM `role_api`
        WHERE `api_id` IN (
            SELECT `id` FROM `api`
            WHERE `path` IN (
                '/api/v1/app_user/common-phrase-review/list',
                '/api/v1/app_user/common-phrase-review/get',
                '/api/v1/app_user/common-phrase-review/review'
            )
        );

        DELETE FROM `api`
        WHERE `path` IN (
            '/api/v1/app_user/common-phrase-review/list',
            '/api/v1/app_user/common-phrase-review/get',
            '/api/v1/app_user/common-phrase-review/review'
        );

        DELETE FROM `menu`
        WHERE `path` = 'common-phrase-review' AND `component` = '/operation/common-phrase-review';

        DROP TABLE IF EXISTS `app_user_common_phrase`;
    """
