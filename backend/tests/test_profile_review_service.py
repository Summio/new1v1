from app.services.profile_review_service import (
    apply_approved_profile_review_items,
    build_profile_review_payload,
    review_items_have_pending,
    update_review_item_status,
)


def test_build_profile_review_payload_splits_changed_profile_fields_and_album_items() -> None:
    payload = build_profile_review_payload(
        current={
            "nickname": "旧昵称",
            "avatar": "/uploads/profile/1/avatar-old.jpg",
            "signature": "旧签名",
            "album_photos": [
                "/uploads/profile/1/a.jpg",
                "/uploads/profile/1/b.jpg",
            ],
            "cover_url": "/uploads/profile/1/a.jpg",
        },
        target={
            "nickname": "新昵称",
            "avatar": "/uploads/profile/1/avatar-old.jpg",
            "signature": "新签名",
            "album_photos": [
                "/uploads/profile/1/b.jpg",
                "/uploads/profile/1/c.jpg",
            ],
            "cover_url": "/uploads/profile/1/c.jpg",
        },
    )

    assert payload["before_snapshot"]["nickname"] == "旧昵称"
    assert payload["after_snapshot"]["nickname"] == "新昵称"
    assert [
        (item["field"], item["op"], item["before"], item["after"], item["status"]) for item in payload["review_items"]
    ] == [
        ("nickname", "replace", "旧昵称", "新昵称", "pending"),
        ("signature", "replace", "旧签名", "新签名", "pending"),
        ("album_photos", "add", None, "/uploads/profile/1/c.jpg", "pending"),
    ]


def test_build_profile_review_payload_ignores_album_remove_reorder_and_cover_change() -> None:
    payload = build_profile_review_payload(
        current={
            "nickname": "小喜",
            "avatar": "",
            "signature": "",
            "album_photos": [
                "/uploads/profile/1/a.jpg",
                "/uploads/profile/1/b.jpg",
                "/uploads/profile/1/c.jpg",
            ],
            "cover_url": "/uploads/profile/1/a.jpg",
        },
        target={
            "nickname": "小喜",
            "avatar": "",
            "signature": "",
            "album_photos": ["/uploads/profile/1/c.jpg", "/uploads/profile/1/a.jpg"],
            "cover_url": "/uploads/profile/1/c.jpg",
        },
    )

    assert payload["review_items"] == []


def test_build_profile_review_payload_reviews_added_album_photo_only() -> None:
    payload = build_profile_review_payload(
        current={
            "nickname": "小喜",
            "avatar": "",
            "signature": "",
            "album_photos": ["/uploads/profile/1/a.jpg", "/uploads/profile/1/b.jpg"],
            "cover_url": "/uploads/profile/1/a.jpg",
        },
        target={
            "nickname": "小喜",
            "avatar": "",
            "signature": "",
            "album_photos": ["/uploads/profile/1/b.jpg", "/uploads/profile/1/c.jpg"],
            "cover_url": "/uploads/profile/1/c.jpg",
        },
    )

    assert [(item["field"], item["op"], item["after"]) for item in payload["review_items"]] == [
        ("album_photos", "add", "/uploads/profile/1/c.jpg"),
    ]


def test_update_review_item_status_does_not_require_reject_reason() -> None:
    payload = build_profile_review_payload(
        current={
            "nickname": "旧昵称",
            "avatar": "",
            "signature": "",
            "album_photos": [],
            "cover_url": "",
        },
        target={
            "nickname": "新昵称",
            "avatar": "",
            "signature": "",
            "album_photos": [],
            "cover_url": "",
        },
    )

    items = update_review_item_status(
        payload["review_items"],
        item_id="nickname",
        status="rejected",
        reviewed_by=7,
    )

    assert items[0]["status"] == "rejected"
    assert items[0]["review_remark"] == ""
    assert items[0]["reviewed_by"] == 7
    assert not review_items_have_pending(items)


def test_apply_approved_profile_review_items_writes_only_approved_items() -> None:
    payload = build_profile_review_payload(
        current={
            "nickname": "旧昵称",
            "avatar": "/uploads/profile/1/old-avatar.jpg",
            "signature": "旧签名",
            "album_photos": [
                "/uploads/profile/1/a.jpg",
                "/uploads/profile/1/b.jpg",
            ],
            "cover_url": "/uploads/profile/1/a.jpg",
        },
        target={
            "nickname": "新昵称",
            "avatar": "/uploads/profile/1/new-avatar.jpg",
            "signature": "新签名",
            "album_photos": [
                "/uploads/profile/1/b.jpg",
                "/uploads/profile/1/c.jpg",
            ],
            "cover_url": "/uploads/profile/1/c.jpg",
        },
    )
    status_by_field = {
        "nickname": "approved",
        "avatar": "rejected",
        "signature": "approved",
        "album_photos:add": "approved",
    }
    reviewed_items = []
    for item in payload["review_items"]:
        key = item["field"] if item["field"] != "album_photos" else f"{item['field']}:{item['op']}"
        reviewed_items.append({**item, "status": status_by_field[key]})

    update_data = apply_approved_profile_review_items(
        before_snapshot=payload["before_snapshot"],
        after_snapshot=payload["after_snapshot"],
        review_items=reviewed_items,
    )

    assert update_data == {
        "nickname": "新昵称",
        "signature": "新签名",
        "album_photos": [
            "/uploads/profile/1/b.jpg",
            "/uploads/profile/1/c.jpg",
        ],
        "cover_url": "/uploads/profile/1/c.jpg",
    }


def test_apply_approved_profile_review_items_keeps_reordered_existing_album_when_add_rejected() -> None:
    payload = build_profile_review_payload(
        current={
            "nickname": "小喜",
            "avatar": "",
            "signature": "",
            "album_photos": [
                "/uploads/profile/1/a.jpg",
                "/uploads/profile/1/b.jpg",
                "/uploads/profile/1/c.jpg",
            ],
            "cover_url": "/uploads/profile/1/a.jpg",
        },
        target={
            "nickname": "小喜",
            "avatar": "",
            "signature": "",
            "album_photos": [
                "/uploads/profile/1/c.jpg",
                "/uploads/profile/1/b.jpg",
                "/uploads/profile/1/d.jpg",
            ],
            "cover_url": "/uploads/profile/1/d.jpg",
        },
    )
    reviewed_items = [{**item, "status": "rejected"} for item in payload["review_items"]]

    update_data = apply_approved_profile_review_items(
        before_snapshot=payload["before_snapshot"],
        after_snapshot=payload["after_snapshot"],
        review_items=reviewed_items,
    )

    assert update_data == {
        "album_photos": [
            "/uploads/profile/1/c.jpg",
            "/uploads/profile/1/b.jpg",
        ],
        "cover_url": "/uploads/profile/1/c.jpg",
    }
