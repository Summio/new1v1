from typing import Any, List, Optional

from fastapi.responses import JSONResponse


class Success(JSONResponse):
    def __init__(
        self,
        code: int = 200,
        msg: str = "success",
        data: Optional[Any] = None,
        **kwargs,
    ):
        content = {"code": code, "msg": msg, "data": data}
        content.update(kwargs)
        super().__init__(content=content, status_code=code)


class Fail(JSONResponse):
    def __init__(
        self,
        code: int = 400,
        msg: str = "error",
        data: Optional[Any] = None,
        **kwargs,
    ):
        content = {"code": code, "msg": msg, "data": data}
        content.update(kwargs)
        super().__init__(content=content, status_code=code)


class SuccessExtra(JSONResponse):
    """
    统一分页响应格式，匹配设计文档：
    {
        "code": 200,
        "msg": "success",
        "data": {},
        "rows": [],
        "current": 1,
        "total": 0,
        "has_more": false
    }
    """

    def __init__(
        self,
        code: int = 200,
        msg: str = "success",
        data: Optional[Any] = None,
        rows: Optional[List] = None,
        current: int = 1,
        total: int = 0,
        has_more: bool = False,
        **kwargs,
    ):
        content = {
            "code": code,
            "msg": msg,
            "data": data,
            "rows": rows if rows is not None else [],
            "current": current,
            "total": total,
            "has_more": has_more,
        }
        content.update(kwargs)
        super().__init__(content=content, status_code=code)
