import contextvars

from starlette.background import BackgroundTasks

CTX_USER_ID: contextvars.ContextVar[int] = contextvars.ContextVar("user_id", default=0)
CTX_APP_USER_ID: contextvars.ContextVar[int] = contextvars.ContextVar("app_user_id", default=0)
CTX_APP_USER_OBJ: contextvars.ContextVar = contextvars.ContextVar("app_user_obj", default=None)
CTX_BG_TASKS: contextvars.ContextVar[BackgroundTasks] = contextvars.ContextVar("bg_task", default=None)
