import ast
import time
import unittest
from pathlib import Path

from jose import jwt

from app.core.app_auth import create_app_access_token
from app.settings.config import settings


class AppAuthTokenPolicyTests(unittest.TestCase):
    def test_access_token_default_expire_minutes_follow_settings(self) -> None:
        token = create_app_access_token(user_id=1)
        claims = jwt.get_unverified_claims(token)
        exp = int(claims["exp"])
        now = int(time.time())

        actual_minutes = round((exp - now) / 60)
        expected_minutes = int(settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES)
        self.assertAlmostEqual(actual_minutes, expected_minutes, delta=2)

    def test_bootstrap_router_should_not_require_auth_dependency(self) -> None:
        source_path = Path(__file__).resolve().parents[1] / "app" / "api" / "v1" / "app" / "__init__.py"
        tree = ast.parse(source_path.read_text(encoding="utf-8"))

        bootstrap_call = None
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            if not isinstance(node.func, ast.Attribute):
                continue
            if node.func.attr != "include_router":
                continue
            if not node.args:
                continue
            arg0 = node.args[0]
            if isinstance(arg0, ast.Name) and arg0.id == "bootstrap_router":
                bootstrap_call = node
                break

        self.assertIsNotNone(bootstrap_call, "未找到 bootstrap_router 的 include_router 调用")
        has_dependencies = any(
            isinstance(kw, ast.keyword) and kw.arg == "dependencies"
            for kw in (bootstrap_call.keywords if bootstrap_call else [])
        )
        self.assertFalse(has_dependencies, "bootstrap_router 不应强制依赖 DependAppAuth")
