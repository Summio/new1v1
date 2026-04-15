from app.core.crud import CRUDBase
from app.models.system_config import SystemConfig
from app.schemas.system_config import SystemConfigCreate, SystemConfigUpdate


class SystemConfigController(CRUDBase[SystemConfig, SystemConfigCreate, SystemConfigUpdate]):
    def __init__(self):
        super().__init__(model=SystemConfig)

    async def get_by_key(self, key: str) -> SystemConfig | None:
        return await self.model.filter(cfg_key=key).first()


system_config_controller = SystemConfigController()
