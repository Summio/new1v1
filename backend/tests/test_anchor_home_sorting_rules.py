from datetime import datetime
from types import SimpleNamespace

from app.api.v1.app.anchor import _anchor_sort_key


def _user(
    user_id: int,
    *,
    reviewed_at: datetime | None = None,
    recommend_weight: int = 0,
):
    return SimpleNamespace(
        id=user_id,
        anchor_reviewed_at=reviewed_at,
        recommend_weight=recommend_weight,
    )


def test_active_section_keeps_online_sorted_by_online_since() -> None:
    old_online = _user(1, reviewed_at=datetime(2026, 1, 1))
    new_online = _user(2, reviewed_at=datetime(2026, 1, 2))
    offline = _user(3, reviewed_at=datetime(2026, 5, 1))

    users = [offline, old_online, new_online]
    users.sort(
        key=lambda user: _anchor_sort_key(
            user,
            "active",
            online_ids={1, 2},
            online_since_map={1: 100, 2: 200},
        ),
        reverse=True,
    )

    assert [user.id for user in users] == [2, 1, 3]


def test_active_section_sorts_offline_by_latest_reviewed_at() -> None:
    old_offline_with_high_id = _user(99, reviewed_at=datetime(2026, 1, 1))
    new_offline_with_low_id = _user(2, reviewed_at=datetime(2026, 5, 1))

    users = [old_offline_with_high_id, new_offline_with_low_id]
    users.sort(
        key=lambda user: _anchor_sort_key(
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
        key=lambda user: _anchor_sort_key(
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
        key=lambda user: _anchor_sort_key(
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
        key=lambda user: _anchor_sort_key(user, "active", set(), {}),
        reverse=True,
    )
    new_order = sorted(
        users,
        key=lambda user: _anchor_sort_key(user, "new", set(), {}),
        reverse=True,
    )

    assert [user.id for user in active_order] == [2, 99]
    assert [user.id for user in new_order] == [2, 99]
