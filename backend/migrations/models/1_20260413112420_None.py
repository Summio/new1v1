from tortoise import BaseDBAsyncClient

RUN_IN_TRANSACTION = True


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE TABLE IF NOT EXISTS `api` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `path` VARCHAR(190) NOT NULL COMMENT 'API路径',
    `method` VARCHAR(6) NOT NULL COMMENT '请求方法',
    `summary` VARCHAR(250) NOT NULL COMMENT '请求简介',
    `tags` VARCHAR(250) NOT NULL COMMENT 'API标签',
    KEY `idx_api_created_78d19f` (`created_at`),
    KEY `idx_api_updated_643c8b` (`updated_at`),
    KEY `idx_api_path_9ed611` (`path`),
    KEY `idx_api_method_a46dfb` (`method`),
    KEY `idx_api_summary_400f73` (`summary`),
    KEY `idx_api_tags_04ae27` (`tags`)
) CHARACTER SET utf8mb4;
CREATE TABLE IF NOT EXISTS `app_user` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `phone` VARCHAR(20) NOT NULL UNIQUE COMMENT '手机号(登录账号)',
    `password` VARCHAR(128) NOT NULL COMMENT '密码(加密)',
    `nickname` VARCHAR(30) COMMENT '昵称',
    `avatar` VARCHAR(500) COMMENT '头像URL',
    `gender` VARCHAR(10) COMMENT 'male/female/secret' DEFAULT 'secret',
    `balance` INT NOT NULL COMMENT '钱包余额(分)' DEFAULT 0,
    `status` VARCHAR(20) COMMENT 'normal/banned' DEFAULT 'normal',
    `ban_reason` VARCHAR(500) COMMENT '封禁原因',
    `last_login` DATETIME(6) COMMENT '最后登录时间',
    KEY `idx_app_user_created_000ee6` (`created_at`),
    KEY `idx_app_user_updated_d54e28` (`updated_at`),
    KEY `idx_app_user_phone_00544c` (`phone`),
    KEY `idx_app_user_status_3cc12d` (`status`)
) CHARACTER SET utf8mb4 COMMENT='App 用户（普通用户 + 主播）';
CREATE TABLE IF NOT EXISTS `anchor` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `is_online` BOOL NOT NULL COMMENT '是否在线' DEFAULT 0,
    `call_price` INT NOT NULL COMMENT '每分钟通话价格(分)' DEFAULT 100,
    `intro` VARCHAR(500) COMMENT '主播简介',
    `tags` JSON COMMENT '标签列表',
    `avatar` VARCHAR(500) COMMENT '头像URL',
    `online_at` DATETIME(6) COMMENT '最近上线时间',
    `apply_status` VARCHAR(20) NOT NULL COMMENT 'pending/approved/rejected' DEFAULT 'pending',
    `apply_at` DATETIME(6) COMMENT '申请时间',
    `reviewed_at` DATETIME(6) COMMENT '审核时间',
    `reject_reason` VARCHAR(500) COMMENT '拒绝原因',
    `app_user_id` BIGINT NOT NULL UNIQUE,
    CONSTRAINT `fk_anchor_app_user_1090901a` FOREIGN KEY (`app_user_id`) REFERENCES `app_user` (`id`) ON DELETE CASCADE,
    KEY `idx_anchor_created_d63aae` (`created_at`),
    KEY `idx_anchor_updated_db14f9` (`updated_at`),
    KEY `idx_anchor_is_onli_6ef924` (`is_online`),
    KEY `idx_anchor_apply_s_052374` (`apply_status`)
) CHARACTER SET utf8mb4 COMMENT='主播资料（关联AppUser）';
CREATE TABLE IF NOT EXISTS `auditlog` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `user_id` INT NOT NULL COMMENT '用户ID',
    `username` VARCHAR(64) NOT NULL COMMENT '用户名称' DEFAULT '',
    `module` VARCHAR(64) NOT NULL COMMENT '功能模块' DEFAULT '',
    `summary` VARCHAR(128) NOT NULL COMMENT '请求描述' DEFAULT '',
    `method` VARCHAR(10) NOT NULL COMMENT '请求方法' DEFAULT '',
    `path` VARCHAR(255) NOT NULL COMMENT '请求路径' DEFAULT '',
    `status` INT NOT NULL COMMENT '状态码' DEFAULT -1,
    `response_time` INT NOT NULL COMMENT '响应时间(单位ms)' DEFAULT 0,
    `request_args` JSON COMMENT '请求参数',
    `response_body` JSON COMMENT '返回数据',
    KEY `idx_auditlog_created_cc33d0` (`created_at`),
    KEY `idx_auditlog_updated_2f871f` (`updated_at`),
    KEY `idx_auditlog_user_id_4b93fa` (`user_id`),
    KEY `idx_auditlog_usernam_b187b3` (`username`),
    KEY `idx_auditlog_status_2a72d2` (`status`)
) CHARACTER SET utf8mb4;
CREATE TABLE IF NOT EXISTS `call_record` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `caller_id` BIGINT NOT NULL COMMENT '主叫用户ID',
    `callee_id` BIGINT NOT NULL COMMENT '被叫用户ID(主播)',
    `status` VARCHAR(20) NOT NULL COMMENT 'pending/ongoing/ended/failed/timeout' DEFAULT 'pending',
    `duration` INT NOT NULL COMMENT '通话时长(秒)' DEFAULT 0,
    `total_fee` INT NOT NULL COMMENT '总费用(分)' DEFAULT 0,
    `end_reason` VARCHAR(50) COMMENT '结束原因',
    KEY `idx_call_record_created_c57564` (`created_at`),
    KEY `idx_call_record_updated_358938` (`updated_at`),
    KEY `idx_call_record_caller__035a06` (`caller_id`),
    KEY `idx_call_record_callee__834718` (`callee_id`),
    KEY `idx_call_record_status_45333b` (`status`)
) CHARACTER SET utf8mb4 COMMENT='通话记录';
CREATE TABLE IF NOT EXISTS `dept` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `name` VARCHAR(20) NOT NULL UNIQUE COMMENT '部门名称',
    `desc` VARCHAR(500) COMMENT '备注',
    `is_deleted` BOOL NOT NULL COMMENT '软删除标记' DEFAULT 0,
    `order` INT NOT NULL COMMENT '排序' DEFAULT 0,
    `parent_id` INT NOT NULL COMMENT '父部门ID' DEFAULT 0,
    KEY `idx_dept_created_4b11cf` (`created_at`),
    KEY `idx_dept_updated_0c0bd1` (`updated_at`),
    KEY `idx_dept_name_c2b9da` (`name`),
    KEY `idx_dept_is_dele_466228` (`is_deleted`),
    KEY `idx_dept_order_ddabe1` (`order`),
    KEY `idx_dept_parent__a71a57` (`parent_id`)
) CHARACTER SET utf8mb4;
CREATE TABLE IF NOT EXISTS `deptclosure` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `ancestor` INT NOT NULL COMMENT '父代',
    `descendant` INT NOT NULL COMMENT '子代',
    `level` INT NOT NULL COMMENT '深度' DEFAULT 0,
    KEY `idx_deptclosure_created_96f6ef` (`created_at`),
    KEY `idx_deptclosure_updated_41fc08` (`updated_at`),
    KEY `idx_deptclosure_ancesto_fbc4ce` (`ancestor`),
    KEY `idx_deptclosure_descend_2ae8b1` (`descendant`),
    KEY `idx_deptclosure_level_ae16b2` (`level`)
) CHARACTER SET utf8mb4;
CREATE TABLE IF NOT EXISTS `gift` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `name` VARCHAR(50) NOT NULL COMMENT '礼物名称',
    `icon` VARCHAR(500) NOT NULL COMMENT '礼物图标URL',
    `price` INT NOT NULL COMMENT '价格(分)',
    `svga_url` VARCHAR(500) COMMENT 'SVGA动画URL',
    `is_active` BOOL NOT NULL COMMENT '是否上架' DEFAULT 1,
    KEY `idx_gift_name_6ffc8c` (`name`),
    KEY `idx_gift_price_890380` (`price`)
) CHARACTER SET utf8mb4 COMMENT='礼物配置';
CREATE TABLE IF NOT EXISTS `gift_record` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `sender_id` BIGINT NOT NULL COMMENT '发送者ID',
    `receiver_id` BIGINT NOT NULL COMMENT '接收者ID',
    `gift_id` BIGINT NOT NULL COMMENT '礼物ID',
    `gift_name` VARCHAR(50) NOT NULL COMMENT '礼物名称',
    `price` INT NOT NULL COMMENT '价格(分)',
    KEY `idx_gift_record_created_e292fe` (`created_at`),
    KEY `idx_gift_record_updated_cacad6` (`updated_at`),
    KEY `idx_gift_record_sender__7a021e` (`sender_id`),
    KEY `idx_gift_record_receive_ef37c2` (`receiver_id`)
) CHARACTER SET utf8mb4 COMMENT='礼物记录';
CREATE TABLE IF NOT EXISTS `menu` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `name` VARCHAR(20) NOT NULL COMMENT '菜单名称',
    `remark` JSON COMMENT '保留字段',
    `menu_type` VARCHAR(7) COMMENT '菜单类型',
    `icon` VARCHAR(100) COMMENT '菜单图标',
    `path` VARCHAR(100) NOT NULL COMMENT '菜单路径',
    `order` INT NOT NULL COMMENT '排序' DEFAULT 0,
    `parent_id` INT NOT NULL COMMENT '父菜单ID' DEFAULT 0,
    `is_hidden` BOOL NOT NULL COMMENT '是否隐藏' DEFAULT 0,
    `component` VARCHAR(100) NOT NULL COMMENT '组件',
    `keepalive` BOOL NOT NULL COMMENT '存活' DEFAULT 1,
    `redirect` VARCHAR(100) COMMENT '重定向',
    KEY `idx_menu_created_b6922b` (`created_at`),
    KEY `idx_menu_updated_e6b0a1` (`updated_at`),
    KEY `idx_menu_name_b9b853` (`name`),
    KEY `idx_menu_path_bf95b2` (`path`),
    KEY `idx_menu_order_606068` (`order`),
    KEY `idx_menu_parent__bebd15` (`parent_id`)
) CHARACTER SET utf8mb4;
CREATE TABLE IF NOT EXISTS `recharge_order` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `user_id` BIGINT NOT NULL COMMENT '用户ID',
    `order_no` VARCHAR(64) NOT NULL UNIQUE COMMENT '订单号',
    `amount` INT NOT NULL COMMENT '充值金额(分)',
    `status` VARCHAR(20) NOT NULL COMMENT 'pending/paid/cancelled/refunded' DEFAULT 'pending',
    `pay_channel` VARCHAR(20) COMMENT '支付渠道: wx/alipay',
    `paid_at` DATETIME(6) COMMENT '支付时间',
    KEY `idx_recharge_or_created_145bb7` (`created_at`),
    KEY `idx_recharge_or_updated_bbbd68` (`updated_at`),
    KEY `idx_recharge_or_user_id_84798e` (`user_id`),
    KEY `idx_recharge_or_order_n_4b84c3` (`order_no`),
    KEY `idx_recharge_or_status_8b1aa4` (`status`)
) CHARACTER SET utf8mb4 COMMENT='充值订单';
CREATE TABLE IF NOT EXISTS `role` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `name` VARCHAR(20) NOT NULL UNIQUE COMMENT '角色名称',
    `desc` VARCHAR(500) COMMENT '角色描述',
    KEY `idx_role_created_7f5f71` (`created_at`),
    KEY `idx_role_updated_5dd337` (`updated_at`),
    KEY `idx_role_name_e5618b` (`name`)
) CHARACTER SET utf8mb4;
CREATE TABLE IF NOT EXISTS `user` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `username` VARCHAR(20) NOT NULL UNIQUE COMMENT '用户名称',
    `alias` VARCHAR(30) COMMENT '姓名',
    `email` VARCHAR(190) NOT NULL UNIQUE COMMENT '邮箱',
    `phone` VARCHAR(20) COMMENT '电话',
    `password` VARCHAR(128) COMMENT '密码',
    `is_active` BOOL NOT NULL COMMENT '是否激活' DEFAULT 1,
    `is_superuser` BOOL NOT NULL COMMENT '是否为超级管理员' DEFAULT 0,
    `last_login` DATETIME(6) COMMENT '最后登录时间',
    `dept_id` INT COMMENT '部门ID',
    KEY `idx_user_created_b19d59` (`created_at`),
    KEY `idx_user_updated_dfdb43` (`updated_at`),
    KEY `idx_user_usernam_9987ab` (`username`),
    KEY `idx_user_alias_6f9868` (`alias`),
    KEY `idx_user_email_1b4f1c` (`email`),
    KEY `idx_user_phone_4e3ecc` (`phone`),
    KEY `idx_user_is_acti_83722a` (`is_active`),
    KEY `idx_user_is_supe_b8a218` (`is_superuser`),
    KEY `idx_user_last_lo_af118a` (`last_login`),
    KEY `idx_user_dept_id_d4490b` (`dept_id`)
) CHARACTER SET utf8mb4;
CREATE TABLE IF NOT EXISTS `withdraw_apply` (
    `id` BIGINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `created_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    `updated_at` DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    `user_id` BIGINT NOT NULL COMMENT '用户ID',
    `amount` INT NOT NULL COMMENT '提现金额(分)',
    `bank_name` VARCHAR(50) COMMENT '银行名称',
    `account_no` VARCHAR(50) COMMENT '银行账号',
    `real_name` VARCHAR(30) COMMENT '真实姓名',
    `status` VARCHAR(20) NOT NULL COMMENT 'pending/processed/rejected' DEFAULT 'pending',
    `processed_at` DATETIME(6) COMMENT '处理时间',
    KEY `idx_withdraw_ap_created_737ba5` (`created_at`),
    KEY `idx_withdraw_ap_updated_2c7534` (`updated_at`),
    KEY `idx_withdraw_ap_user_id_afe4a9` (`user_id`),
    KEY `idx_withdraw_ap_status_e38075` (`status`)
) CHARACTER SET utf8mb4 COMMENT='提现申请';
CREATE TABLE IF NOT EXISTS `aerich` (
    `id` INT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    `version` VARCHAR(255) NOT NULL,
    `app` VARCHAR(100) NOT NULL,
    `content` JSON NOT NULL
) CHARACTER SET utf8mb4;
CREATE TABLE IF NOT EXISTS `role_menu` (
    `role_id` BIGINT NOT NULL,
    `menu_id` BIGINT NOT NULL,
    FOREIGN KEY (`role_id`) REFERENCES `role` (`id`) ON DELETE CASCADE,
    FOREIGN KEY (`menu_id`) REFERENCES `menu` (`id`) ON DELETE CASCADE,
    UNIQUE KEY `uidx_role_menu_role_id_90801c` (`role_id`, `menu_id`)
) CHARACTER SET utf8mb4;
CREATE TABLE IF NOT EXISTS `role_api` (
    `role_id` BIGINT NOT NULL,
    `api_id` BIGINT NOT NULL,
    FOREIGN KEY (`role_id`) REFERENCES `role` (`id`) ON DELETE CASCADE,
    FOREIGN KEY (`api_id`) REFERENCES `api` (`id`) ON DELETE CASCADE,
    UNIQUE KEY `uidx_role_api_role_id_ba4286` (`role_id`, `api_id`)
) CHARACTER SET utf8mb4;
CREATE TABLE IF NOT EXISTS `user_role` (
    `user_id` BIGINT NOT NULL,
    `role_id` BIGINT NOT NULL,
    FOREIGN KEY (`user_id`) REFERENCES `user` (`id`) ON DELETE CASCADE,
    FOREIGN KEY (`role_id`) REFERENCES `role` (`id`) ON DELETE CASCADE,
    UNIQUE KEY `uidx_user_role_user_id_d0bad3` (`user_id`, `role_id`)
) CHARACTER SET utf8mb4;"""


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        """


MODELS_STATE = (
    "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"
)
