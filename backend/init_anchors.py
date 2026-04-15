import asyncio
from tortoise import Tortoise
from app.settings.config import settings
from app.models.admin import User, Anchor

async def run():
    # 初始化 Tortoise
    await Tortoise.init(config=settings.TORTOISE_ORM)
    
    try:
        # 1. 找到刚才创建的测试用户
        user = await User.filter(phone="13800138000").first()
        if not user:
            print("Error: User 13800138000 not found. Run add_test_user.py first.")
            return

        # 2. 更新用户角色为主播
        user.app_role = "anchor"
        user.username = "小欢喜"
        user.gender = "female"
        user.avatar = "https://img.freepik.com/free-photo/portrait-beautiful-young-woman-with-long-brown-hair_231208-124.jpg"
        user.anchor_intro = "欢迎来到我的直播间，很高兴认识你~"
        user.call_price = 200 # 2元/分钟
        await user.save()
        print(f"Updated user {user.username} to anchor role.")

        # 3. 创建或更新主播表数据
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
            anchor.call_price = 200
            anchor.avatar = user.avatar
            await anchor.save()
            print("Updated existing anchor record to online.")
        else:
            print("Created new online anchor record.")

        # 4. 再创建一个假主播以便测试列表分页
        user2, _ = await User.get_or_create(
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
        await Anchor.get_or_create(
            user=user2,
            defaults={
                "is_online": True,
                "call_price": 300,
                "intro": "我是甜心，想和你聊天~",
                "avatar": user2.avatar,
            }
        )
        print("Created another test anchor '甜心主播'.")

    except Exception as e:
        print(f"Error: {e}")

    await Tortoise.close_connections()

if __name__ == "__main__":
    asyncio.run(run())
