import json
import re
from datetime import datetime
from typing import Any, AsyncGenerator

from fastapi import FastAPI
from fastapi.responses import JSONResponse, Response
from fastapi.routing import APIRoute
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.types import ASGIApp, Receive, Scope, Send

from app.models.admin import AuditLog

from .bgtask import BgTasks

SENSITIVE_FIELDS = {
    "password",
    "old_password",
    "new_password",
    "token",
    "authorization",
    "access_token",
    "refresh_token",
    "account_no",
    "id_card",
    "bank_card",
    "real_name",
    "bank_name",
}


def sanitize_sensitive_data(data: Any) -> Any:
    if isinstance(data, dict):
        sanitized: dict[str, Any] = {}
        for key, value in data.items():
            if key.lower() in SENSITIVE_FIELDS:
                sanitized[key] = "***"
            else:
                sanitized[key] = sanitize_sensitive_data(value)
        return sanitized
    if isinstance(data, list):
        return [sanitize_sensitive_data(item) for item in data]
    return data


class SimpleBaseMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        request = Request(scope, receive=receive)

        response = await self.before_request(request) or self.app
        await response(request.scope, request.receive, send)
        await self.after_request(request)

    async def before_request(self, request: Request):
        return self.app

    async def after_request(self, request: Request):
        return None


class BackGroundTaskMiddleware(SimpleBaseMiddleware):
    async def before_request(self, request):
        await BgTasks.init_bg_tasks_obj()

    async def after_request(self, request):
        await BgTasks.execute_tasks()


class HttpAuditLogMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, methods: list[str], exclude_paths: list[str]):
        super().__init__(app)
        self.methods = methods
        self.exclude_paths = exclude_paths
        self.audit_log_paths = ["/api/v1/auditlog/list"]
        self.max_body_size = 1024 * 1024  # 1MB 响应体大小限制

    async def get_request_args(self, request: Request) -> dict:
        args = {}
        # 获取查询参数
        for key, value in request.query_params.items():
            args[key] = value

        # 获取请求体
        if request.method in ["POST", "PUT", "PATCH"]:
            content_type = (request.headers.get("content-type") or "").lower()
            is_json = "application/json" in content_type
            is_multipart = "multipart/form-data" in content_type
            is_urlencoded = "application/x-www-form-urlencoded" in content_type
            is_form = is_multipart or is_urlencoded

            if is_json:
                try:
                    body = await request.json()
                    if isinstance(body, dict):
                        args.update(body)
                except (json.JSONDecodeError, UnicodeDecodeError, ValueError, TypeError):
                    # 非法 JSON 请求体不阻断主流程，避免影响业务接口可用性
                    pass
            elif is_form:
                # 关键修复：
                # multipart 请求体是可消费流，若在中间件提前读取，可能导致下游 File(...) 参数解析失败
                # 因此对 multipart 仅记录占位信息，不在这里读取 request.form()
                if is_multipart:
                    args["__form_data__"] = "[multipart omitted]"
                    return args
                try:
                    body = await request.form()
                    for k, v in body.items():
                        if hasattr(v, "filename"):  # 文件上传行为
                            args[k] = v.filename
                        elif isinstance(v, list) and v and hasattr(v[0], "filename"):
                            args[k] = [file.filename for file in v]
                        else:
                            args[k] = v
                except Exception:
                    pass

        return args

    async def get_response_body(self, request: Request, response: Response) -> Any:
        # P3-1: 优先从 ResponseBodyCacheMiddleware 缓存的响应中读取
        cached_response = getattr(request.state, "_cached_response", None)
        if cached_response is not None and hasattr(cached_response, "body"):
            response_to_read = cached_response
        else:
            response_to_read = response

        # 检查Content-Length
        content_length = response_to_read.headers.get("content-length")
        if content_length and int(content_length) > self.max_body_size:
            return {"code": 0, "msg": "Response too large to log", "data": None}

        if hasattr(response_to_read, "body") and response_to_read.body is not None:
            body = response_to_read.body
        else:
            body_chunks = []
            async for chunk in response_to_read.body_iterator:
                if not isinstance(chunk, bytes):
                    chunk = chunk.encode(response_to_read.charset)
                body_chunks.append(chunk)

            response_to_read.body_iterator = self._async_iter(body_chunks)
            body = b"".join(body_chunks)

        if any(request.url.path.startswith(path) for path in self.audit_log_paths):
            try:
                data = self.lenient_json(body)
                # 只保留基本信息，去除详细的响应内容
                if isinstance(data, dict):
                    data.pop("response_body", None)
                    if "data" in data and isinstance(data["data"], list):
                        for item in data["data"]:
                            item.pop("response_body", None)
                return data
            except Exception:
                return None

        return self.lenient_json(body)

    def lenient_json(self, v: Any) -> Any:
        if isinstance(v, bytes):
            try:
                return json.loads(v)
            except (ValueError, TypeError, UnicodeDecodeError):
                return {"_binary_bytes": len(v)}
        if isinstance(v, str):
            try:
                return json.loads(v)
            except (ValueError, TypeError):
                return {"_text": v}
        return v

    async def _async_iter(self, items: list[bytes]) -> AsyncGenerator[bytes, None]:
        for item in items:
            yield item

    async def get_request_log(self, request: Request, response: Response) -> dict:
        """
        根据request和response对象获取对应的日志记录数据。
        优先复用 CTX 中的已认证用户信息（避免重复 JWT 解码），
        若无 context 则尝试从 header 解码。
        """
        data: dict = {"path": request.url.path, "status": response.status_code, "method": request.method}
        # 路由信息
        app: FastAPI = request.app
        for route in app.routes:
            if (
                isinstance(route, APIRoute)
                and route.path_regex.match(request.url.path)
                and request.method in route.methods
            ):
                data["module"] = ",".join(route.tags)
                data["summary"] = route.summary

        # M2 修复：直接复用 CTX 中已解码的用户信息，避免重复 JWT 解码
        from app.core.ctx import CTX_APP_USER_ID, CTX_APP_USER_OBJ

        ctx_user_id = CTX_APP_USER_ID.get()
        ctx_user = CTX_APP_USER_OBJ.get()
        if ctx_user:
            # App 用户（认证用户/普通用户）
            data["user_id"] = ctx_user_id or 0
            data["username"] = (
                ctx_user.nickname
                if hasattr(ctx_user, "nickname") and ctx_user.nickname
                else (ctx_user.phone if hasattr(ctx_user, "phone") and ctx_user.phone else str(ctx_user.id))
            )
        else:
            data["user_id"] = 0
            data["username"] = ""
        return data

    async def before_request(self, request: Request):
        request_args = await self.get_request_args(request)
        request.state.request_args = request_args

    async def after_request(self, request: Request, response: Response, process_time: int):
        # 静态资源（如上传图片）不做审计落库，避免无意义日志与二进制解析风险
        if request.url.path.startswith("/uploads/"):
            return response

        if request.method in self.methods:
            for path in self.exclude_paths:
                if re.search(path, request.url.path, re.I) is not None:
                    return
            data: dict = await self.get_request_log(request=request, response=response)
            data["response_time"] = process_time

            data["request_args"] = sanitize_sensitive_data(request.state.request_args)
            data["response_body"] = sanitize_sensitive_data(await self.get_response_body(request, response))
            await AuditLog.create(**data)

        return response

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        start_time: datetime = datetime.now()
        await self.before_request(request)
        response = await call_next(request)
        end_time: datetime = datetime.now()
        process_time = int((end_time.timestamp() - start_time.timestamp()) * 1000)
        await self.after_request(request, response, process_time)
        return response


class ResponseBodyCacheMiddleware(BaseHTTPMiddleware):
    """P3-2: 将响应体预读到内存，避免后续中间件重复消费 body_iterator。"""

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        response = await call_next(request)

        if not hasattr(response, "body") or response.body is None:
            body_chunks = []
            async for chunk in response.body_iterator:
                if not isinstance(chunk, bytes):
                    chunk = chunk.encode(response.charset or "utf-8")
                body_chunks.append(chunk)
            body_bytes = b"".join(body_chunks)

            headers = {}
            if hasattr(response, "init_headers"):
                headers = dict(response.init_headers())
            if hasattr(response, "raw_headers"):
                headers = dict(response.raw_headers)

            media_type = getattr(response, "media_type", "application/json")

            response = Response(
                content=body_bytes,
                status_code=response.status_code,
                headers=headers,
                media_type=media_type,
            )

        request.state._cached_response = response
        return response


class AppFriendlyStatusMiddleware(BaseHTTPMiddleware):
    """App 接口统一使用 HTTP 200，业务错误通过 code/msg 表达。"""

    @staticmethod
    def _is_app_request(request: Request) -> bool:
        return request.url.path.startswith("/api/v1/app/")

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        response = await call_next(request)
        if not self._is_app_request(request) or response.status_code < 400:
            return response

        # P3-2: 优先从 ResponseBodyCacheMiddleware 缓存的响应中读取
        cached_response = getattr(request.state, "_cached_response", None)
        if cached_response is not None and hasattr(cached_response, "body") and cached_response.body is not None:
            body = cached_response.body
        elif hasattr(response, "body") and response.body is not None:
            body = response.body
        else:
            chunks = []
            async for chunk in response.body_iterator:
                if not isinstance(chunk, bytes):
                    chunk = chunk.encode(response.charset)
                chunks.append(chunk)
            body = b"".join(chunks)

        payload: dict[str, Any]
        try:
            raw = json.loads(body or b"{}")
            if isinstance(raw, dict):
                payload = raw
            else:
                payload = {}
        except Exception:
            payload = {}

        payload.setdefault("code", response.status_code)
        payload.setdefault("msg", "请求失败，请稍后重试")
        payload.setdefault("data", None)
        return JSONResponse(content=payload, status_code=200)
