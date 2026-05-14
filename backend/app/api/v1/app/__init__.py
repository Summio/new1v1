from fastapi import APIRouter, Depends

from app.core.app_auth import DependAppAuth

from .agreement import router as agreement_router
from .bootstrap import router as bootstrap_router
from .call import router as call_router
from .certification import router as certification_router
from .certified_user import router as certified_user_router
from .complaint import router as complaint_router
from .feedback import router as feedback_router
from .flirt import router as flirt_router
from .gift import router as gift_router
from .im import router as im_router
from .initial_profile import router as initial_profile_router
from .location import router as location_router
from .moment import router as moment_router
from .notification import router as notification_router
from .password import router as password_router
from .privacy import router as privacy_router
from .ranking import router as ranking_router
from .register import router as register_router
from .review_entry import router as review_entry_router
from .rtc import router as rtc_router
from .user import router as user_router
from .wallet import router as wallet_router

app_router = APIRouter()

# register_router: 注册接口无需认证
app_router.include_router(register_router, prefix="")
app_router.include_router(
    initial_profile_router, prefix="/register/initial-profile", dependencies=[Depends(DependAppAuth)]
)
# user_router: /login 无需认证，/user/info 需要 DependAppAuth
app_router.include_router(user_router, prefix="")
app_router.include_router(bootstrap_router, prefix="")
app_router.include_router(location_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(certified_user_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(flirt_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(certification_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(call_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(gift_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(wallet_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(im_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(rtc_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(agreement_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(privacy_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(password_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(moment_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(notification_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(ranking_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(review_entry_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(feedback_router, prefix="", dependencies=[Depends(DependAppAuth)])
app_router.include_router(complaint_router, prefix="", dependencies=[Depends(DependAppAuth)])
