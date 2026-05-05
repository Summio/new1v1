from app.core.crud import CRUDBase
from app.models.admin import Gift
from app.schemas.gift import GiftCreate, GiftUpdate


class GiftController(CRUDBase[Gift, GiftCreate, GiftUpdate]):
    def __init__(self):
        super().__init__(model=Gift)


gift_controller = GiftController()
