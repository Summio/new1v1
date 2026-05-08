from tortoise import BaseDBAsyncClient


async def upgrade(db: BaseDBAsyncClient) -> str:
    return """
        CREATE INDEX `idx_app_user_anchor_rec_perf` ON `app_user` (`status`, `is_anchor`, `is_recommended`, `recommend_weight`, `anchor_reviewed_at`, `id`);
        CREATE INDEX `idx_app_user_anchor_new_perf` ON `app_user` (`status`, `is_anchor`, `anchor_reviewed_at`, `id`);
        CREATE INDEX `idx_call_record_caller_status_updated` ON `call_record` (`caller_id`, `status`, `updated_at`);
        CREATE INDEX `idx_call_record_callee_status_updated` ON `call_record` (`callee_id`, `status`, `updated_at`);
        CREATE INDEX `idx_call_record_income_created` ON `call_record` (`income_anchor_user_id`, `created_at`);
        CREATE INDEX `idx_call_record_payer_created` ON `call_record` (`payer_user_id`, `created_at`);
        CREATE INDEX `idx_moments_user_created_id` ON `moments` (`user_id`, `created_at`, `id`);
        CREATE INDEX `idx_moment_media_moment_sort` ON `moment_media` (`moment_id`, `sort_order`);
        CREATE INDEX `idx_recharge_user_status_created` ON `recharge_order` (`user_id`, `status`, `created_at`);
        CREATE INDEX `idx_withdraw_user_status_created` ON `withdraw_apply` (`user_id`, `status`, `created_at`);
        CREATE INDEX `idx_gift_record_sender_created` ON `gift_record` (`sender_id`, `created_at`);
        CREATE INDEX `idx_gift_record_receiver_created` ON `gift_record` (`receiver_id`, `created_at`);
        CREATE INDEX `idx_im_text_sender_status_created` ON `im_text_message_charge_record` (`sender_id`, `status`, `created_at`);
        CREATE INDEX `idx_im_text_receiver_status_created` ON `im_text_message_charge_record` (`receiver_id`, `status`, `created_at`);
    """


async def downgrade(db: BaseDBAsyncClient) -> str:
    return """
        DROP INDEX `idx_im_text_receiver_status_created` ON `im_text_message_charge_record`;
        DROP INDEX `idx_im_text_sender_status_created` ON `im_text_message_charge_record`;
        DROP INDEX `idx_gift_record_receiver_created` ON `gift_record`;
        DROP INDEX `idx_gift_record_sender_created` ON `gift_record`;
        DROP INDEX `idx_withdraw_user_status_created` ON `withdraw_apply`;
        DROP INDEX `idx_recharge_user_status_created` ON `recharge_order`;
        DROP INDEX `idx_moment_media_moment_sort` ON `moment_media`;
        DROP INDEX `idx_moments_user_created_id` ON `moments`;
        DROP INDEX `idx_call_record_payer_created` ON `call_record`;
        DROP INDEX `idx_call_record_income_created` ON `call_record`;
        DROP INDEX `idx_call_record_callee_status_updated` ON `call_record`;
        DROP INDEX `idx_call_record_caller_status_updated` ON `call_record`;
        DROP INDEX `idx_app_user_anchor_new_perf` ON `app_user`;
        DROP INDEX `idx_app_user_anchor_rec_perf` ON `app_user`;
    """
