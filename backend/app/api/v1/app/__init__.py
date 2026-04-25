from fastapi import APIRouter, Depends

from app.core.app_auth import DependAppAuth

from .bootstrap import router as bootstrap_router
from .anchor import router as anchor_router
from .anchor_apply import router as anchor_apply_router
from .call import router as call_router
from .gift import router as gift_router
from .im import router as im_router
from .moment import router as moment_router
from .register import router as register_router
from .rtc import router as rtc_router
from .user import router as user_router
from .wallet import router as wallet_router
from .agreement import router as agreement_router
from .privacy import router as privacy_router
from .password import router as password_router

app_router = APIRouter()

# register_router: 注册接口无需认证
app_router.include_router(register_router, prefix="")
# user_router: /login 无需认证，/user/info 需要 DependAppAuth
app_router.include_router(user_router, prefix="")
app_router.include_router(bootstrap_router, prefix="")
app_router.include_router(anchor_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(anchor_apply_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(call_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(gift_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(wallet_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(im_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(rtc_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(agreement_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(privacy_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(password_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(moment_router, prefix="", dependencies=[Depends(DependAppAuth)])
