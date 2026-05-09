"""
添加测试数据：1个用户 + 20个主播
运行方式: cd backend && python scripts/seed_test_data.py
"""

import asyncio
import random
import sys

sys.path.insert(0, ".")

from tortoise import Tortoise

from app.models import Anchor, AppUser, Gift
from app.utils.password import get_password_hash

# 真实头像 URL（randomuser.me）
# 测试用户用固定头像，主播头像根据性别分配
TEST_USER_AVATAR = "https://randomuser.me/api/portraits/women/0.jpg"

ANCHOR_AVATARS = {
    # female anchors (gender=female)
    "female": [
        "https://randomuser.me/api/portraits/women/1.jpg",
        "https://randomuser.me/api/portraits/women/2.jpg",
        "https://randomuser.me/api/portraits/women/3.jpg",
        "https://randomuser.me/api/portraits/women/4.jpg",
        "https://randomuser.me/api/portraits/women/5.jpg",
        "https://randomuser.me/api/portraits/women/6.jpg",
        "https://randomuser.me/api/portraits/women/7.jpg",
        "https://randomuser.me/api/portraits/women/8.jpg",
        "https://randomuser.me/api/portraits/women/9.jpg",
        "https://randomuser.me/api/portraits/women/10.jpg",
        "https://randomuser.me/api/portraits/women/11.jpg",
        "https://randomuser.me/api/portraits/women/12.jpg",
        "https://randomuser.me/api/portraits/women/13.jpg",
        "https://randomuser.me/api/portraits/women/14.jpg",
        "https://randomuser.me/api/portraits/women/15.jpg",
        "https://randomuser.me/api/portraits/women/16.jpg",
        "https://randomuser.me/api/portraits/women/17.jpg",
        "https://randomuser.me/api/portraits/women/18.jpg",
        "https://randomuser.me/api/portraits/women/19.jpg",
        "https://randomuser.me/api/portraits/women/20.jpg",
        "https://randomuser.me/api/portraits/women/21.jpg",
        "https://randomuser.me/api/portraits/women/22.jpg",
        "https://randomuser.me/api/portraits/women/23.jpg",
        "https://randomuser.me/api/portraits/women/24.jpg",
        "https://randomuser.me/api/portraits/women/25.jpg",
    ],
    # male anchors (gender=male)
    "male": [
        "https://randomuser.me/api/portraits/men/1.jpg",
        "https://randomuser.me/api/portraits/men/2.jpg",
        "https://randomuser.me/api/portraits/men/3.jpg",
        "https://randomuser.me/api/portraits/men/4.jpg",
        "https://randomuser.me/api/portraits/men/5.jpg",
        "https://randomuser.me/api/portraits/men/6.jpg",
        "https://randomuser.me/api/portraits/men/7.jpg",
        "https://randomuser.me/api/portraits/men/8.jpg",
        "https://randomuser.me/api/portraits/men/9.jpg",
        "https://randomuser.me/api/portraits/men/10.jpg",
        "https://randomuser.me/api/portraits/men/11.jpg",
        "https://randomuser.me/api/portraits/men/12.jpg",
        "https://randomuser.me/api/portraits/men/13.jpg",
        "https://randomuser.me/api/portraits/men/14.jpg",
        "https://randomuser.me/api/portraits/men/15.jpg",
        "https://randomuser.me/api/portraits/men/16.jpg",
        "https://randomuser.me/api/portraits/men/17.jpg",
        "https://randomuser.me/api/portraits/men/18.jpg",
        "https://randomuser.me/api/portraits/men/19.jpg",
        "https://randomuser.me/api/portraits/men/20.jpg",
        "https://randomuser.me/api/portraits/men/21.jpg",
        "https://randomuser.me/api/portraits/men/22.jpg",
        "https://randomuser.me/api/portraits/men/23.jpg",
        "https://randomuser.me/api/portraits/men/24.jpg",
        "https://randomuser.me/api/portraits/men/25.jpg",
    ],
}

ANCHOR_INTROS = [
    "声音好听，喜欢聊天",
    "夜猫子，随时在线",
    "喜欢音乐，唱歌好听",
    "温暖治愈系",
    "有趣的灵魂万里挑一",
    "喜欢电影和旅行",
    "擅长倾听，是个好树洞",
    "开朗活泼，爱笑",
    "深夜陪伴，治愈心灵",
    "声音温柔，人美心善",
    "会做饭的吃货",
    "游戏达人，游戏带飞",
    "健身爱好者",
    "读书爱好者",
    "摄影爱好者",
    "绘画达人",
    "音乐达人",
    "舞蹈爱好者",
    "宠物爱好者",
    "户外运动爱好者",
]

ANCHOR_TAGS = [
    ["温柔", "治愈"],
    ["活泼", "开朗"],
    ["唱歌", "音乐"],
    ["游戏", "带飞"],
    ["电影", "旅行"],
    ["健身", "运动"],
    ["美食", "烹饪"],
    ["绘画", "艺术"],
    ["摄影", "旅行"],
    ["宠物", "猫奴"],
    ["读书", "文艺"],
    ["舞蹈", "运动"],
    ["电竞", "游戏"],
    ["户外", "旅行"],
    ["萌系", "可爱"],
    ["御姐", "高冷"],
    ["暖男", "体贴"],
    ["学霸", "智慧"],
    ["吃货", "美食"],
    ["旅行", "探索"],
]


async def seed():
    await Tortoise.init(
        db_url="mysql://root:123456@localhost:3306/huanxi",
        modules={"models": ["app.models"]},
    )
    await Tortoise.generate_schemas()

    print("连接数据库成功，开始插入数据...")

    # ===== 清理旧数据（开发环境） =====
    await AppUser.all().delete()
    await Anchor.all().delete()
    print("已清理旧数据")

    # ===== 1. 创建测试用户 =====
    test_user = await AppUser.create(
        phone="13800000001",
        password=get_password_hash("123456"),
        nickname="测试用户",
        avatar=TEST_USER_AVATAR,
        gender="male",
        coins=10000,  # 100元
        status="normal",
    )
    print(f"创建用户: id={test_user.id}, phone={test_user.phone}, coins={test_user.coins}分")

    # ===== 2. 创建 20 个主播 =====
    anchor_count = 20
    created_anchors = []

    female_idx = 0
    male_idx = 0

    for i in range(1, anchor_count + 1):
        phone = f"138000000{i + 1:02d}"  # 13800000002 ~ 13800000021
        gender = random.choice(["male", "female"])

        # 根据性别分配头像索引
        if gender == "female":
            avatar_url = ANCHOR_AVATARS["female"][female_idx % len(ANCHOR_AVATARS["female"])]
            female_idx += 1
        else:
            avatar_url = ANCHOR_AVATARS["male"][male_idx % len(ANCHOR_AVATARS["male"])]
            male_idx += 1

        user = await AppUser.create(
            phone=phone,
            password=get_password_hash("123456"),
            nickname=f"主播{i:02d}",
            avatar=avatar_url,
            gender=gender,
            status="normal",
            is_anchor=True,
        )

        # 约 60% 在线
        is_online = random.random() < 0.6

        anchor = await Anchor.create(
            app_user=user,
            is_online=is_online,
            call_price=random.choice([50, 100, 150, 200]),  # 0.5~2元/分钟
            intro=ANCHOR_INTROS[i - 1],
            tags=ANCHOR_TAGS[i - 1],
            avatar=avatar_url,
            apply_status="approved",
        )
        created_anchors.append(anchor)
        online_str = "在线" if is_online else "离线"
        print(f"  主播{i:02d}: id={anchor.id}, phone={phone}, 价格={anchor.call_price}分/分钟, {online_str}")

    # ===== 3. 创建礼物数据 =====
    gifts_data = [
        ("小花", 10, "flower"),
        ("巧克力", 50, "chocolate"),
        ("爱心", 100, "heart"),
        ("戒指", 500, "ring"),
        ("汽车", 1000, "car"),
        ("城堡", 5000, "castle"),
    ]

    for name, price, icon_key in gifts_data:
        existing = await Gift.filter(name=name).first()
        if not existing:
            await Gift.create(
                name=name,
                icon=f"https://img.icons.earth/200/{icon_key}.png",
                price=price,
                is_active=True,
            )

    print(f"\n共创建 {1 + len(created_anchors)} 个用户")
    print(f"共创建 {len(created_anchors)} 个主播")
    print(f"共创建 {len(gifts_data)} 个礼物")
    print("\n测试账号:")
    print("  用户: 13800000001 / 123456")
    print("  主播: 13800000002 ~ 13800000021 / 123456")

    await Tortoise.close_connections()
    print("\n完成!")


if __name__ == "__main__":
    asyncio.run(seed())
