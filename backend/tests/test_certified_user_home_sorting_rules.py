from datetime import datetime
from types import SimpleNamespace

from app.api.v1.app.certified_user import _availability_sort_rank, _certified_user_sort_key


def _user(
    user_id: int,
    *,
    reviewed_at: datetime | None = None,
    recommend_weight: int = 0,
    video_dnd_enabled: bool = False,
):
    return SimpleNamespace(
        id=user_id,
        certification_reviewed_at=reviewed_at,
        recommend_weight=recommend_weight,
        video_dnd_enabled=video_dnd_enabled,
    )


def test_active_section_keeps_online_sorted_by_online_since() -> None:
    old_online = _user(1, reviewed_at=datetime(2026, 1, 1))
    new_online = _user(2, reviewed_at=datetime(2026, 1, 2))
    offline = _user(3, reviewed_at=datetime(2026, 5, 1))

    users = [offline, old_online, new_online]
    users.sort(
        key=lambda user: _certified_user_sort_key(
            user,
            "active",
            online_ids={1, 2},
            online_since_map={1: 100, 2: 200},
        ),
        reverse=True,
    )

    assert [user.id for user in users] == [2, 1, 3]


def test_availability_sort_rank_groups_online_and_busy_above_dnd_above_offline() -> None:
    online = _user(1)
    busy = _user(2)
    dnd = _user(3, video_dnd_enabled=True)
    offline = _user(4, video_dnd_enabled=True)

    assert _availability_sort_rank(online, {1, 2, 3}) == 2
    assert _availability_sort_rank(busy, {1, 2, 3}) == 2
    assert _availability_sort_rank(dnd, {1, 2, 3}) == 1
    assert _availability_sort_rank(offline, {1, 2, 3}) == 0


def test_recommend_section_sorts_dnd_between_online_and_offline() -> None:
    online = _user(1, recommend_weight=10, reviewed_at=datetime(2026, 1, 1))
    dnd = _user(2, recommend_weight=99, reviewed_at=datetime(2026, 1, 2), video_dnd_enabled=True)
    offline = _user(3, recommend_weight=999, reviewed_at=datetime(2026, 1, 3))

    users = [offline, dnd, online]
    users.sort(
        key=lambda user: _certified_user_sort_key(
            user,
            "recommend",
            online_ids={1, 2},
            online_since_map={},
        ),
        reverse=True,
    )

    assert [user.id for user in users] == [1, 2, 3]


def test_new_section_keeps_online_and_busy_same_rank_with_review_sorting() -> None:
    old_online = _user(1, reviewed_at=datetime(2026, 1, 1))
    new_busy = _user(2, reviewed_at=datetime(2026, 5, 1))
    dnd = _user(3, reviewed_at=datetime(2026, 12, 1), video_dnd_enabled=True)

    users = [dnd, old_online, new_busy]
    users.sort(
        key=lambda user: _certified_user_sort_key(
            user,
            "new",
            online_ids={1, 2, 3},
            online_since_map={},
        ),
        reverse=True,
    )

    assert [user.id for user in users] == [2, 1, 3]


def test_active_section_sorts_offline_by_latest_reviewed_at() -> None:
    old_offline_with_high_id = _user(99, reviewed_at=datetime(2026, 1, 1))
    new_offline_with_low_id = _user(2, reviewed_at=datetime(2026, 5, 1))

    users = [old_offline_with_high_id, new_offline_with_low_id]
    users.sort(
        key=lambda user: _certified_user_sort_key(
            user,
            "active",
            online_ids=set(),
            online_since_map={},
        ),
        reverse=True,
    )

    assert [user.id for user in users] == [2, 99]


def test_recommend_section_sorts_offline_by_recommend_weight() -> None:
    low_weight = _user(1, recommend_weight=10, reviewed_at=datetime(2026, 5, 1))
    high_weight = _user(2, recommend_weight=99, reviewed_at=datetime(2026, 1, 1))

    users = [low_weight, high_weight]
    users.sort(
        key=lambda user: _certified_user_sort_key(
            user,
            "recommend",
            online_ids=set(),
            online_since_map={},
        ),
        reverse=True,
    )

    assert [user.id for user in users] == [2, 1]


def test_new_section_sorts_offline_by_latest_reviewed_at() -> None:
    old_offline_with_high_id = _user(99, reviewed_at=datetime(2026, 1, 1))
    new_offline_with_low_id = _user(2, reviewed_at=datetime(2026, 5, 1))

    users = [old_offline_with_high_id, new_offline_with_low_id]
    users.sort(
        key=lambda user: _certified_user_sort_key(
            user,
            "new",
            online_ids=set(),
            online_since_map={},
        ),
        reverse=True,
    )

    assert [user.id for user in users] == [2, 99]


def test_active_and_new_use_same_offline_review_sorting() -> None:
    old_offline_with_high_id = _user(99, reviewed_at=datetime(2026, 1, 1))
    new_offline_with_low_id = _user(2, reviewed_at=datetime(2026, 5, 1))
    users = [old_offline_with_high_id, new_offline_with_low_id]

    active_order = sorted(
        users,
        key=lambda user: _certified_user_sort_key(user, "active", set(), {}),
        reverse=True,
    )
    new_order = sorted(
        users,
        key=lambda user: _certified_user_sort_key(user, "new", set(), {}),
        reverse=True,
    )

    assert [user.id for user in active_order] == [2, 99]
    assert [user.id for user in new_order] == [2, 99]
