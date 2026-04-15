import asyncio
from tortoise import Tortoise
from app.settings.config import settings
from app.models.admin import User

async def run():
    await Tortoise.init(config=settings.TORTOISE_ORM)
    users = await User.all()
    print(f"Total users: {len(users)}")
    for u in users:
        print(f"ID: {u.id}, Username: {u.username}, Phone: {u.phone}, Role: {u.app_role}")
    await Tortoise.close_connections()

if __name__ == "__main__":
    asyncio.run(run())
