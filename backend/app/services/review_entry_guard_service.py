from app.models import AppUserProfileReviewApply, Moment

PROFILE_REVIEW_PENDING_MESSAGE = "您有资料编辑申请待审核，请审核完成后再提交"
MOMENT_REVIEW_PENDING_MESSAGE = "您有动态待审核，请审核完成后再提交"


async def has_pending_profile_review(user_id: int) -> bool:
    return await AppUserProfileReviewApply.filter(
        user_id=user_id,
        status__in=["pending", "reviewing"],
    ).exists()


async def has_pending_moment_review(user_id: int) -> bool:
    return await Moment.filter(user_id=user_id, review_status="pending").exists()


def build_entry_status(*, can_enter: bool, status: str = "none", reason_code: str = "", msg: str = "") -> dict:
    return {
        "can_enter": can_enter,
        "status": status,
        "reason_code": reason_code,
        "msg": msg,
    }


async def build_review_entry_status(user_id: int) -> dict:
    has_profile_review = await has_pending_profile_review(user_id)
    has_moment_review = await has_pending_moment_review(user_id)

    return {
        "profile_edit": build_entry_status(
            can_enter=not has_profile_review,
            status="pending" if has_profile_review else "none",
            reason_code="profile_review_pending" if has_profile_review else "",
            msg=PROFILE_REVIEW_PENDING_MESSAGE if has_profile_review else "",
        ),
        "moment_publish": build_entry_status(
            can_enter=not has_moment_review,
            status="pending" if has_moment_review else "none",
            reason_code="moment_review_pending" if has_moment_review else "",
            msg=MOMENT_REVIEW_PENDING_MESSAGE if has_moment_review else "",
        ),
    }
