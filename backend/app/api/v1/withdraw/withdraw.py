from fastapi import APIRouter, Query
from tortoise.expressions import F, Q
from tortoise.transactions import in_transaction

from app.core.ctx import CTX_USER_ID
from app.core.time_utils import now_local_naive
from app.log import logger
from app.models import AppUser, WithdrawAccount, WithdrawApply
from app.schemas.app_api import (
    WithdrawAccountListItem,
    WithdrawAccountReviewIn,
    WithdrawListItem,
    WithdrawReviewIn,
)
from app.schemas.base import Fail, Success, SuccessExtra

router = APIRouter()


def mask_account_no(account_no: str) -> str:
    return account_no if len(account_no) <= 4 else f"****{account_no[-4:]}"


@router.get("/list", summary="提现申请列表")
async def withdraw_list(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    status: str = Query("", description="状态筛选：pending/paid/rejected"),
    user_id: int = Query(None, description="用户ID"),
    real_name: str = Query("", description="真实姓名"),
    account_no: str = Query("", description="支付宝账号"),
):
    q = Q()
    if status:
        if status == "paid":
            q &= Q(status__in=["paid", "approved"])
        else:
            q &= Q(status=status)
    if user_id:
        q &= Q(user_id=user_id)
    if real_name:
        q &= Q(real_name__contains=real_name)
    if account_no:
        q &= Q(account_no__contains=account_no)

    total = await WithdrawApply.filter(q).count()
    records = await WithdrawApply.filter(q).order_by("-created_at").offset((page - 1) * page_size).limit(page_size)

    # 批量获取用户昵称
    user_ids = list({r.user_id for r in records})
    users_map = {}
    if user_ids:
        users = await AppUser.filter(id__in=user_ids).all()
        users_map = {u.id: (u.nickname or "").strip() or (u.phone or "").strip() or f"用户{u.id}" for u in users}

    items = []
    for r in records:
        raw_account = r.account_no or ""
        items.append(
            WithdrawListItem(
                id=r.id,
                user_id=r.user_id,
                amount=int(r.amount),
                bank_name=r.bank_name or "",
                account_no=raw_account,
                account_no_masked=mask_account_no(raw_account),
                real_name=r.real_name or "",
                payment_qr_code=r.payment_qr_code or "",
                status=r.status,
                review_remark=r.review_remark or "",
                processed_by=r.processed_by,
                created_at=r.created_at,
                processed_at=r.processed_at,
                username=users_map.get(r.user_id),
            )
        )

    return SuccessExtra(
        data=[item.model_dump(mode="json") for item in items], total=total, page=page, page_size=page_size
    )


@router.get("/account/list", summary="提现账户审核列表")
async def withdraw_account_list(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    status: str = Query("pending", description="状态筛选：pending/approved/rejected/all"),
    user_id: int = Query(None, description="用户ID"),
    real_name: str = Query("", description="真实姓名"),
    account_no: str = Query("", description="支付宝账号"),
):
    q = Q()
    if status and status != "all":
        q &= Q(status=status)
    if user_id:
        q &= Q(user_id=user_id)
    if real_name:
        q &= Q(real_name__contains=real_name)
    if account_no:
        q &= Q(account_no__contains=account_no)

    total = await WithdrawAccount.filter(q).count()
    records = await WithdrawAccount.filter(q).order_by("-updated_at").offset((page - 1) * page_size).limit(page_size)

    user_ids = list({r.user_id for r in records})
    users_map = {}
    if user_ids:
        users = await AppUser.filter(id__in=user_ids).all()
        users_map = {u.id: (u.nickname or "").strip() or (u.phone or "").strip() or f"用户{u.id}" for u in users}

    items = []
    for r in records:
        raw_account = r.account_no or ""
        items.append(
            WithdrawAccountListItem(
                id=r.id,
                user_id=r.user_id,
                real_name=r.real_name or "",
                account_no=raw_account,
                account_no_masked=mask_account_no(raw_account),
                payment_qr_code=r.payment_qr_code or "",
                status=r.status,
                review_remark=r.review_remark or "",
                reviewed_by=r.reviewed_by,
                created_at=r.created_at,
                updated_at=r.updated_at,
                reviewed_at=r.reviewed_at,
                username=users_map.get(r.user_id),
            )
        )

    return SuccessExtra(
        data=[item.model_dump(mode="json") for item in items], total=total, page=page, page_size=page_size
    )


@router.post("/account/review", summary="审核提现账户")
async def withdraw_account_review(req_in: WithdrawAccountReviewIn):
    action = req_in.action.strip().lower()
    if action not in ("approve", "reject"):
        return Fail(code=400, msg="action 必须为 approve 或 reject")
    review_remark = (req_in.review_remark or req_in.review_reason or "").strip()
    if action == "reject" and not review_remark:
        return Fail(code=400, msg="请填写驳回原因")

    account = await WithdrawAccount.filter(id=req_in.account_id).first()
    if not account:
        return Fail(code=404, msg="提现账户不存在")
    if account.status != "pending":
        return Fail(code=400, msg=f"该账户状态为「{account.status}」，无法重复审核")

    account.status = "approved" if action == "approve" else "rejected"
    account.reviewed_by = CTX_USER_ID.get()
    account.reviewed_at = now_local_naive()
    account.review_remark = review_remark
    await account.save(update_fields=["status", "reviewed_by", "reviewed_at", "review_remark"])

    return Success(msg="审核通过" if action == "approve" else "已驳回")


@router.post("/review", summary="审核提现申请")
async def withdraw_review(req_in: WithdrawReviewIn):
    action = req_in.action.strip().lower()
    if action not in ("approve", "reject"):
        return Fail(code=400, msg="action 必须为 approve 或 reject")
    review_remark = (req_in.review_remark or req_in.review_reason or "").strip()
    if action == "reject" and not review_remark:
        return Fail(code=400, msg="请填写驳回原因")

    async with in_transaction() as conn:
        withdraw = await WithdrawApply.filter(id=req_in.withdraw_id).using_db(conn).first()
        if not withdraw:
            return Fail(code=404, msg="提现申请不存在")

        if withdraw.status != "pending":
            return Fail(code=400, msg=f"该申请状态为「{withdraw.status}」，无法重复操作")

        if action == "reject":
            # 拒绝：解冻钻石，退款到可用余额
            # B-5 修复：使用 GREATEST 避免 frozen_diamonds - amount 后变为负数
            await AppUser.filter(id=withdraw.user_id).using_db(conn).update(
                diamonds=F("diamonds") + withdraw.amount,
                frozen_diamonds=F("frozen_diamonds") - withdraw.amount,
            )
            # 安全检查：若减后 frozen_diamonds 为负，说明数据异常（记录日志）
            updated_user = await AppUser.filter(id=withdraw.user_id).using_db(conn).first()
            if updated_user and updated_user.frozen_diamonds < 0:
                logger.warning(
                    "withdraw reject: frozen_diamonds went negative for user_id={} withdraw_id={}",
                    withdraw.user_id,
                    withdraw.id,
                )
                # 修正为 0
                await AppUser.filter(id=withdraw.user_id).using_db(conn).update(
                    frozen_diamonds=0,
                )
            withdraw.status = "rejected"
            withdraw.processed_at = now_local_naive()
            withdraw.processed_by = CTX_USER_ID.get()
            withdraw.review_remark = review_remark
            await withdraw.save(
                using_db=conn,
                update_fields=["status", "processed_at", "processed_by", "review_remark"],
            )
            return Success(msg="已拒绝申请，钻石已解冻")

        # 通过即确认已打款：冻结钻石正式扣除
        await AppUser.filter(id=withdraw.user_id).using_db(conn).update(
            frozen_diamonds=F("frozen_diamonds") - withdraw.amount,
        )
        updated_user = await AppUser.filter(id=withdraw.user_id).using_db(conn).first()
        if updated_user and updated_user.frozen_diamonds < 0:
            logger.warning(
                "withdraw paid: frozen_diamonds went negative for user_id={} withdraw_id={}",
                withdraw.user_id,
                withdraw.id,
            )
            await AppUser.filter(id=withdraw.user_id).using_db(conn).update(
                frozen_diamonds=0,
            )
        withdraw.status = "paid"
        withdraw.processed_at = now_local_naive()
        withdraw.processed_by = CTX_USER_ID.get()
        withdraw.review_remark = review_remark
        await withdraw.save(
            using_db=conn,
            update_fields=["status", "processed_at", "processed_by", "review_remark"],
        )
        return Success(msg="已确认打款")
