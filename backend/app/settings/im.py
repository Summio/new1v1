import typing

from pydantic_settings import BaseSettings


class IMSettings(BaseSettings):
    """腾讯 IM 配置"""

    model_config = {"env_file": ".env", "extra": "ignore"}

    # 腾讯 IM 配置（生产环境必填）
    IM_SDKAPPID: typing.Optional[int] = None
    IM_SECRETKEY: typing.Optional[str] = None

    @property
    def is_configured(self) -> bool:
        """检查 IM 配置是否完整"""
        return bool(self.IM_SDKAPPID and self.IM_SECRETKEY)


im_settings = IMSettings()
