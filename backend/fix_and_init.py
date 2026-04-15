import asyncio
from tortoise import Tortoise
from app.settings.config import settings
from app.models.admin import User, Anchor

async def run():
    await Tortoise.init(config=settings.TORTOISE_ORM)
    
    try:
        # 1. 修复之前创建的 testuser，确保手机号正确
        user = await User.filter(username="testuser").first()
        if user:
            user.phone = "13800138000"
            user.app_role = "anchor"
            user.username = "小欢喜"
            user.gender = "female"
            user.avatar = "https://img.freepik.com/free-photo/portrait-beautiful-young-woman-with-long-brown-hair_231208-124.jpg"
            user.anchor_intro = "欢迎来到我的直播间，很高兴认识你~"
            user.call_price = 200
            await user.save()
            print(f"Fixed user {user.username} with phone 13800138000")

            # 2. 确保主播表有数据
            anchor, created = await Anchor.get_or_create(
                user=user,
                defaults={
                    "is_online": True,
                    "call_price": 200,
                    "intro": user.anchor_intro,
                    "avatar": user.avatar,
                }
            )
            if not created:
                anchor.is_online = True
                await anchor.save()
            print("Anchor table updated.")

        # 3. 再创建一个主播
        user2, created = await User.get_or_create(
            username="甜心主播",
            defaults={
                "phone": "13911112222",
                "email": "tianxin@example.com",
                "password": "password123",
                "app_role": "anchor",
                "gender": "female",
                "is_active": True,
                "avatar": "https://img.freepik.com/free-photo/pretty-smiling-joyfully-female-with-fair-hair-dressed-casually-looking-with-satisfaction_176420-15187.jpg"
            }
        )
        if not created:
            user2.phone = "13911112222"
            await user2.save()

        await Anchor.get_or_create(
            user=user2,
            defaults={
                "is_online": True,
                "call_price": 300,
                "intro": "我是甜心，想和你聊天~",
                "avatar": user2.avatar,
            }
        )
        print("Test anchor '甜心主播' ready.")

    except Exception as e:
        print(f"Error: {e}")

    await Tortoise.close_connections()

if __name__ == "__main__":
    asyncio.run(run())
