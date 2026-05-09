from fastapi.exceptions import (
    HTTPException,
    RequestValidationError,
    ResponseValidationError,
)
from fastapi.requests import Request
from fastapi.responses import JSONResponse
from tortoise.exceptions import DoesNotExist, IntegrityError


class SettingNotFound(Exception):
    pass


def _is_app_path(path: str) -> bool:
    return path.startswith("/api/v1/app/")


def _app_error_response(code: int, msg: str) -> JSONResponse:
    return JSONResponse(
        content={
            "code": code,
            "msg": msg,
            "data": None,
        },
        status_code=200,
    )


async def DoesNotExistHandle(req: Request, exc: DoesNotExist) -> JSONResponse:
    if _is_app_path(req.url.path):
        return _app_error_response(404, "资源不存在")

    content = dict(
        code=404,
        msg=f"Object has not found, exc: {exc}, query_params: {req.query_params}",
    )
    return JSONResponse(content=content, status_code=404)


async def IntegrityHandle(req: Request, exc: IntegrityError) -> JSONResponse:
    if _is_app_path(req.url.path):
        return _app_error_response(500, "服务繁忙，请稍后重试")

    content = dict(
        code=500,
        msg=f"IntegrityError，{exc}",
    )
    return JSONResponse(content=content, status_code=500)


async def HttpExcHandle(req: Request, exc: HTTPException) -> JSONResponse:
    if _is_app_path(req.url.path):
        msg = exc.detail if exc.status_code < 500 else "服务繁忙，请稍后重试"
        return _app_error_response(exc.status_code, str(msg))

    content = dict(code=exc.status_code, msg=exc.detail, data=None)
    return JSONResponse(content=content, status_code=exc.status_code)


def _build_validation_msg(exc: RequestValidationError) -> str:
    errors = exc.errors()
    if not errors:
        return "请求参数有误，请检查后重试"

    first = errors[0]
    msg = str(first.get("msg", "请求参数有误，请检查后重试"))
    loc = first.get("loc", ())
    err_type = str(first.get("type", ""))

    field = ""
    if isinstance(loc, (list, tuple)) and len(loc) >= 2:
        field = str(loc[-1])

    field_map = {
        "phone": "手机号",
        "password": "密码",
        "gender": "性别",
        "old_password": "旧密码",
        "new_password": "新密码",
        "token": "登录凭证",
    }
    field_cn = field_map.get(field, "")

    # 去除 Pydantic 技术前缀，避免前端展示 "Value error" 这类不友好内容
    if msg.startswith("Value error, "):
        msg = msg.replace("Value error, ", "", 1)

    lower_msg = msg.lower()
    if err_type == "missing" or lower_msg == "field required":
        return f"{field_cn}不能为空" if field_cn else "缺少必要参数"

    if "string should have at least" in lower_msg:
        import re

        match = re.search(r"at least\s+(\d+)", lower_msg)
        if match:
            return f"{field_cn}长度不能少于{match.group(1)}位" if field_cn else f"参数长度不能少于{match.group(1)}位"

    if "string should have at most" in lower_msg:
        import re

        match = re.search(r"at most\s+(\d+)", lower_msg)
        if match:
            return f"{field_cn}长度不能超过{match.group(1)}位" if field_cn else f"参数长度不能超过{match.group(1)}位"

    if "input should be" in lower_msg or "invalid" in lower_msg:
        return f"{field_cn}格式不正确" if field_cn else "参数格式不正确"

    if field_cn:
        if msg.startswith(field_cn):
            return msg
        return f"{field_cn}{msg}" if msg.startswith("长度") else f"{field_cn}：{msg}"

    return msg


async def RequestValidationHandle(req: Request, exc: RequestValidationError) -> JSONResponse:
    # App 侧统一返回业务态错误，避免前端直接展示 HTTP 422。
    if _is_app_path(req.url.path):
        return _app_error_response(400, _build_validation_msg(exc))

    content = dict(code=422, msg=f"RequestValidationError, {exc}", data=None)
    return JSONResponse(content=content, status_code=422)


async def ResponseValidationHandle(req: Request, exc: ResponseValidationError) -> JSONResponse:
    if _is_app_path(req.url.path):
        return _app_error_response(500, "服务繁忙，请稍后重试")

    content = dict(code=500, msg=f"ResponseValidationError, {exc}")
    return JSONResponse(content=content, status_code=500)


async def UnhandledExceptionHandle(req: Request, _: Exception) -> JSONResponse:
    if _is_app_path(req.url.path):
        return _app_error_response(500, "服务繁忙，请稍后重试")

    content = dict(code=500, msg="Internal Server Error", data=None)
    return JSONResponse(content=content, status_code=500)
