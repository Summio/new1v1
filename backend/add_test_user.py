import asyncio
from tortoise import Tortoise
from app.settings.config import settings
from app.models.admin import User
from app.controllers.user import UserCreate, user_controller

async def run():
    # 初始化 Tortoise
    await Tortoise.init(config=settings.TORTOISE_ORM)
    
    # 检查 user 表是否存在
    try:
        user_exists = await User.filter(phone="13800138000").exists()
        if not user_exists:
            print("Creating test user 13800138000...")
            await user_controller.create_user(
                UserCreate(
                    username="testuser",
                    email="test@example.com",
                    phone="13800138000",
                    password="password123",
                    is_active=True,
                )
            )
            print("Test user created successfully!")
        else:
            print("Test user 13800138000 already exists.")
            
        # 也更新 admin 的手机号，以便 admin 也能登录
        admin = await User.filter(username="admin").first()
        if admin:
            admin.phone = "18888888888"
            await admin.save()
            print("Updated admin phone to 18888888888")
            
    except Exception as e:
        print(f"Error: {e}")
        print("Maybe tables are not created yet? Try running 'aerich upgrade' first.")

    await Tortoise.close_connections()

if __name__ == "__main__":
    asyncio.run(run())
