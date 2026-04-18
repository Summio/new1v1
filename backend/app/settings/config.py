import os
import typing
import warnings
from pathlib import Path

from dotenv import load_dotenv
from pydantic_settings import BaseSettings

# 加载 backend/.env 文件（兼容 pydantic-settings v2 不自动加载 .env 的行为）
load_dotenv(Path(__file__).parent.parent.parent / ".env")


class Settings(BaseSettings):
    model_config = {"env_file": ".env", "extra": "ignore"}

    VERSION: str = "0.1.0"
    APP_TITLE: str = "欢喜 (Huanxi) 后台管理"
    PROJECT_NAME: str = "Huanxi Admin"
    APP_DESCRIPTION: str = "1v1付费音视频交友平台后台"

    # CORS 配置：生产环境必须通过环境变量设置具体域名列表，禁止默认允许所有来源
    # 示例：CORS_ORIGINS=https://huanxi.com,https://www.huanxi.com
    _cors_origins = os.getenv("CORS_ORIGINS", "")
    CORS_ORIGINS: typing.List = (
        [origin.strip() for origin in _cors_origins.split(",") if origin.strip()]
        if _cors_origins
        else (["http://localhost:3000", "http://localhost:8080"] if os.getenv("DEBUG", "false").lower() == "true" else [])
    )
    CORS_ALLOW_CREDENTIALS: bool = True
    CORS_ALLOW_METHODS: typing.List = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]
    CORS_ALLOW_HEADERS: typing.List = ["*"]

    # DEBUG 默认关闭，生产环境必须通过环境变量 DEBUG=true 开启
    DEBUG: bool = False

    PROJECT_ROOT: str = os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))
    BASE_DIR: str = os.path.abspath(os.path.join(PROJECT_ROOT, os.pardir))
    LOGS_ROOT: str = os.path.join(BASE_DIR, "app/logs")
    # JWT 配置
    _secret_key = os.getenv("SECRET_KEY", "")
    if not _secret_key:
        if os.getenv("DEBUG", "false").lower() != "true":
            raise ValueError("环境变量 SECRET_KEY 未设置，生产环境必须配置强密钥")
        _secret_key = "dev-only-fallback-key-change-in-prod"
        warnings.warn("使用了开发用 SECRET_KEY，生产环境请通过环境变量 SECRET_KEY 配置", UserWarning, stacklevel=2)
    SECRET_KEY: str = _secret_key
    JWT_ALGORITHM: str = "HS256"
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 30  # 30 days

    # MySQL 配置
    DB_HOST: str = os.getenv("DB_HOST", "localhost")
    DB_PORT: int = int(os.getenv("DB_PORT", "3306"))
    DB_USER: str = os.getenv("DB_USER", "root")
    _db_password = os.getenv("DB_PASSWORD", "")
    if not _db_password:
        if os.getenv("DEBUG", "false").lower() != "true":
            raise ValueError("环境变量 DB_PASSWORD 未设置，生产环境必须配置数据库密码")
        _db_password = "123456"
        warnings.warn("使用了默认数据库密码 123456，生产环境请通过环境变量 DB_PASSWORD 配置", UserWarning, stacklevel=2)
    DB_PASSWORD: str = _db_password
    DB_DATABASE: str = os.getenv("DB_DATABASE", "huanxi")
    DB_POOL_MIN: int = int(os.getenv("DB_POOL_MIN", "5"))
    DB_POOL_MAX: int = int(os.getenv("DB_POOL_MAX", "10"))

    # Redis 配置
    REDIS_HOST: str = "localhost"
    REDIS_PORT: int = 6379
    REDIS_DB: int = 0
    REDIS_PASSWORD: typing.Optional[str] = os.getenv("REDIS_PASSWORD") or None

    # 可信代理 IP 列表（逗号分隔），仅当请求来自这些 IP 时才读取 X-Forwarded-For 头
    # 生产环境建议在内网入口处（Nginx/网关）配置，不填写则完全信任 X-Forwarded-For（有安全风险）
    # 示例：TRUSTED_PROXY_IPS=10.0.0.1,10.0.0.2
    _trusted_proxy_ips = os.getenv("TRUSTED_PROXY_IPS", "")
    TRUSTED_PROXY_IPS: typing.List[str] = (
        [ip.strip() for ip in _trusted_proxy_ips.split(",") if ip.strip()]
        if _trusted_proxy_ips
        else []
    )

    # 通话心跳配置
    HEARTBEAT_INTERVAL: int = int(os.getenv("HEARTBEAT_INTERVAL", "5"))  # 秒

    TORTOISE_ORM: dict = {
        "connections": {
            "mysql": {
                "engine": "tortoise.backends.mysql",
                "credentials": {
                    "host": DB_HOST,
                    "port": DB_PORT,
                    "user": DB_USER,
                    "password": DB_PASSWORD,
                    "database": DB_DATABASE,
                    "minsize": DB_POOL_MIN,
                    "maxsize": DB_POOL_MAX,
                },
            },
        },
        "apps": {
            "models": {
                "models": ["app.models", "aerich.models"],
                "default_connection": "mysql",
            },
        },
        "use_tz": False,
        "timezone": "Asia/Shanghai",
    }
    DATETIME_FORMAT: str = "%Y-%m-%d %H:%M:%S"


    # 腾讯 IM 配置
    # 充值回调 Mock 开关：仅在本地开发/测试环境启用（DEBUG=true 且 ENABLE_MOCK_CALLBACK=true）
    # 生产环境必须接入微信支付/支付宝真实回调，禁用此 Mock
    ENABLE_MOCK_CALLBACK: bool = os.getenv("ENABLE_MOCK_CALLBACK", "false").lower() == "true"
try:
    from app.settings.im import im_settings as im_settings
except ImportError:
    im_settings = None

settings = Settings()
