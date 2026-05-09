"""
更新主播头像为真实感更强的图片
使用 randomuser.me API 提供的高质量头像
运行方式: cd backend && python scripts/update_anchor_avatars.py
"""

import asyncio
import random
import sys

sys.path.insert(0, ".")

from tortoise import Tortoise

from app.models import Anchor, AppUser

# 20个真实感头像 URL（randomuser.me 端口）
# 分为女性(1-70)和男性(1-70)两组
FEMALE_AVATARS = [
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
    "https://randomuser.me/api/portraits/women/26.jpg",
    "https://randomuser.me/api/portraits/women/27.jpg",
    "https://randomuser.me/api/portraits/women/28.jpg",
    "https://randomuser.me/api/portraits/women/29.jpg",
    "https://randomuser.me/api/portraits/women/30.jpg",
    "https://randomuser.me/api/portraits/women/31.jpg",
    "https://randomuser.me/api/portraits/women/32.jpg",
    "https://randomuser.me/api/portraits/women/33.jpg",
    "https://randomuser.me/api/portraits/women/34.jpg",
    "https://randomuser.me/api/portraits/women/35.jpg",
    "https://randomuser.me/api/portraits/women/36.jpg",
    "https://randomuser.me/api/portraits/women/37.jpg",
    "https://randomuser.me/api/portraits/women/38.jpg",
    "https://randomuser.me/api/portraits/women/39.jpg",
    "https://randomuser.me/api/portraits/women/40.jpg",
    "https://randomuser.me/api/portraits/women/41.jpg",
    "https://randomuser.me/api/portraits/women/42.jpg",
    "https://randomuser.me/api/portraits/women/43.jpg",
    "https://randomuser.me/api/portraits/women/44.jpg",
    "https://randomuser.me/api/portraits/women/45.jpg",
    "https://randomuser.me/api/portraits/women/46.jpg",
    "https://randomuser.me/api/portraits/women/47.jpg",
    "https://randomuser.me/api/portraits/women/48.jpg",
    "https://randomuser.me/api/portraits/women/49.jpg",
    "https://randomuser.me/api/portraits/women/50.jpg",
    "https://randomuser.me/api/portraits/women/51.jpg",
    "https://randomuser.me/api/portraits/women/52.jpg",
    "https://randomuser.me/api/portraits/women/53.jpg",
    "https://randomuser.me/api/portraits/women/54.jpg",
    "https://randomuser.me/api/portraits/women/55.jpg",
    "https://randomuser.me/api/portraits/women/56.jpg",
    "https://randomuser.me/api/portraits/women/57.jpg",
    "https://randomuser.me/api/portraits/women/58.jpg",
    "https://randomuser.me/api/portraits/women/59.jpg",
    "https://randomuser.me/api/portraits/women/60.jpg",
    "https://randomuser.me/api/portraits/women/61.jpg",
    "https://randomuser.me/api/portraits/women/62.jpg",
    "https://randomuser.me/api/portraits/women/63.jpg",
    "https://randomuser.me/api/portraits/women/64.jpg",
    "https://randomuser.me/api/portraits/women/65.jpg",
    "https://randomuser.me/api/portraits/women/66.jpg",
    "https://randomuser.me/api/portraits/women/67.jpg",
    "https://randomuser.me/api/portraits/women/68.jpg",
    "https://randomuser.me/api/portraits/women/69.jpg",
    "https://randomuser.me/api/portraits/women/70.jpg",
]

MALE_AVATARS = [
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
    "https://randomuser.me/api/portraits/men/26.jpg",
    "https://randomuser.me/api/portraits/men/27.jpg",
    "https://randomuser.me/api/portraits/men/28.jpg",
    "https://randomuser.me/api/portraits/men/29.jpg",
    "https://randomuser.me/api/portraits/men/30.jpg",
    "https://randomuser.me/api/portraits/men/31.jpg",
    "https://randomuser.me/api/portraits/men/32.jpg",
    "https://randomuser.me/api/portraits/men/33.jpg",
    "https://randomuser.me/api/portraits/men/34.jpg",
    "https://randomuser.me/api/portraits/men/35.jpg",
    "https://randomuser.me/api/portraits/men/36.jpg",
    "https://randomuser.me/api/portraits/men/37.jpg",
    "https://randomuser.me/api/portraits/men/38.jpg",
    "https://randomuser.me/api/portraits/men/39.jpg",
    "https://randomuser.me/api/portraits/men/40.jpg",
    "https://randomuser.me/api/portraits/men/41.jpg",
    "https://randomuser.me/api/portraits/men/42.jpg",
    "https://randomuser.me/api/portraits/men/43.jpg",
    "https://randomuser.me/api/portraits/men/44.jpg",
    "https://randomuser.me/api/portraits/men/45.jpg",
    "https://randomuser.me/api/portraits/men/46.jpg",
    "https://randomuser.me/api/portraits/men/47.jpg",
    "https://randomuser.me/api/portraits/men/48.jpg",
    "https://randomuser.me/api/portraits/men/49.jpg",
    "https://randomuser.me/api/portraits/men/50.jpg",
    "https://randomuser.me/api/portraits/men/51.jpg",
    "https://randomuser.me/api/portraits/men/52.jpg",
    "https://randomuser.me/api/portraits/men/53.jpg",
    "https://randomuser.me/api/portraits/men/54.jpg",
    "https://randomuser.me/api/portraits/men/55.jpg",
    "https://randomuser.me/api/portraits/men/56.jpg",
    "https://randomuser.me/api/portraits/men/57.jpg",
    "https://randomuser.me/api/portraits/men/58.jpg",
    "https://randomuser.me/api/portraits/men/59.jpg",
    "https://randomuser.me/api/portraits/men/60.jpg",
    "https://randomuser.me/api/portraits/men/61.jpg",
    "https://randomuser.me/api/portraits/men/62.jpg",
    "https://randomuser.me/api/portraits/men/63.jpg",
    "https://randomuser.me/api/portraits/men/64.jpg",
    "https://randomuser.me/api/portraits/men/65.jpg",
    "https://randomuser.me/api/portraits/men/66.jpg",
    "https://randomuser.me/api/portraits/men/67.jpg",
    "https://randomuser.me/api/portraits/men/68.jpg",
    "https://randomuser.me/api/portraits/men/69.jpg",
    "https://randomuser.me/api/portraits/men/70.jpg",
]


async def update_avatars():
    await Tortoise.init(
        db_url="mysql://root:123456@localhost:3306/huanxi",
        modules={"models": ["app.models"]},
    )

    print("连接数据库成功，开始更新主播头像...")

    # 打乱头像顺序
    female_pool = FEMALE_AVATARS.copy()
    male_pool = MALE_AVATARS.copy()
    random.shuffle(female_pool)
    random.shuffle(male_pool)

    female_idx = 0
    male_idx = 0

    anchors = await Anchor.all().prefetch_related("app_user")
    total = len(anchors)
    updated = 0

    for anchor in anchors:
        app_user = anchor.app_user

        # 根据性别选择头像
        if app_user.gender == "female":
            avatar_url = female_pool[female_idx % len(female_pool)]
            female_idx += 1
        else:
            avatar_url = male_pool[male_idx % len(male_pool)]
            male_idx += 1

        # 同时更新 AppUser 和 Anchor 的头像
        app_user.avatar = avatar_url
        anchor.avatar = avatar_url
        await app_user.save()
        await anchor.save()

        updated += 1
        status = "在线" if anchor.is_online else "离线"
        print(f"  [{updated}/{total}] {app_user.nickname} ({app_user.gender}) -> {avatar_url} [{status}]")

    print(f"\n完成！共更新 {updated} 个主播的头像")

    await Tortoise.close_connections()


if __name__ == "__main__":
    asyncio.run(update_avatars())
