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

from app.core.app_auth import AppAuthControl
from app.core.dependency import AuthControl
from app.models.admin import AuditLog, User

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
            try:
                body = await request.json()
                args.update(body)
            except json.JSONDecodeError:
                try:
                    body = await request.form()
                    # args.update(body)
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
        # 检查Content-Length
        content_length = response.headers.get("content-length")
        if content_length and int(content_length) > self.max_body_size:
            return {"code": 0, "msg": "Response too large to log", "data": None}

        if hasattr(response, "body"):
            body = response.body
        else:
            body_chunks = []
            async for chunk in response.body_iterator:
                if not isinstance(chunk, bytes):
                    chunk = chunk.encode(response.charset)
                body_chunks.append(chunk)

            response.body_iterator = self._async_iter(body_chunks)
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
        if isinstance(v, (str, bytes)):
            try:
                return json.loads(v)
            except (ValueError, TypeError):
                pass
        return v

    async def _async_iter(self, items: list[bytes]) -> AsyncGenerator[bytes, None]:
        for item in items:
            yield item

    async def get_request_log(self, request: Request, response: Response) -> dict:
        """
        根据request和response对象获取对应的日志记录数据。
        同时支持 Admin Token 和 App Token。
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
        # 获取用户信息 — 优先尝试 App Token，再尝试 Admin Token
        token = request.headers.get("token")
        user_obj = None
        user_type = "unknown"
        if token:
            # 1. 优先尝试 App Token
            try:
                user_obj = await AppAuthControl.is_app_authed(token)
                user_type = "app"
            except Exception:
                pass
            # 2. 降级尝试 Admin Token
            if user_obj is None:
                try:
                    user_obj = await AuthControl.is_authed(token)
                    user_type = "admin"
                except Exception:
                    user_obj = None
        if user_obj is None:
            data["user_id"] = 0
            data["username"] = ""
            return data
        data["user_id"] = user_obj.id
        data["username"] = (
            user_obj.nickname if user_type == "app" and hasattr(user_obj, "nickname")
            else (user_obj.phone if user_type == "app" and hasattr(user_obj, "phone")
            else (user_obj.username if user_type == "admin" and hasattr(user_obj, "username")
            else ""))
        )
        return data

    async def before_request(self, request: Request):
        request_args = await self.get_request_args(request)
        request.state.request_args = request_args

    async def after_request(self, request: Request, response: Response, process_time: int):
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


class AppFriendlyStatusMiddleware(BaseHTTPMiddleware):
    """App 接口统一使用 HTTP 200，业务错误通过 code/msg 表达。"""

    @staticmethod
    def _is_app_request(request: Request) -> bool:
        return request.url.path.startswith("/api/v1/app/")

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        response = await call_next(request)
        if not self._is_app_request(request) or response.status_code < 400:
            return response

        body = b""
        if hasattr(response, "body") and response.body is not None:
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
