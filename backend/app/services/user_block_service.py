from dataclasses import dataclass

from tortoise.expressions import Q

from app.models import UserBlock


@dataclass(frozen=True)
class BlockRelation:
    blocked_by_me: bool = False
    blocked_me: bool = False

    @property
    def interaction_blocked(self) -> bool:
        return self.blocked_by_me or self.blocked_me


class UserBlockError(Exception):
    def __init__(self, code: int, message: str):
        self.code = code
        self.message = message
        super().__init__(message)


async def get_block_relation(actor_id: int, target_id: int) -> BlockRelation:
    if actor_id <= 0 or target_id <= 0 or actor_id == target_id:
        return BlockRelation()
    rows = await UserBlock.filter(
        Q(blocker_id=actor_id, blocked_id=target_id) | Q(blocker_id=target_id, blocked_id=actor_id)
    ).all()
    blocked_by_me = any(int(row.blocker_id) == actor_id and int(row.blocked_id) == target_id for row in rows)
    blocked_me = any(int(row.blocker_id) == target_id and int(row.blocked_id) == actor_id for row in rows)
    return BlockRelation(blocked_by_me=blocked_by_me, blocked_me=blocked_me)


async def ensure_not_blocked(actor_id: int, target_id: int, action_label: str) -> None:
    relation = await get_block_relation(actor_id, target_id)
    if relation.interaction_blocked:
        raise UserBlockError(403, f"你们之间已存在黑名单关系，无法{action_label}")


async def exclude_blocked_user_ids(current_user_id: int) -> list[int]:
    if current_user_id <= 0:
        return []
    rows = await UserBlock.filter(Q(blocker_id=current_user_id) | Q(blocked_id=current_user_id)).all()
    ids: set[int] = set()
    for row in rows:
        blocker_id = int(row.blocker_id)
        blocked_id = int(row.blocked_id)
        ids.add(blocked_id if blocker_id == current_user_id else blocker_id)
    ids.discard(current_user_id)
    return list(ids)
