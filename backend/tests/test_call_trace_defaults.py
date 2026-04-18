import asyncio
import importlib.util
import sys
import types
import unittest
from pathlib import Path


def _install_fake_loguru() -> None:
    module = types.ModuleType("loguru")

    class _Logger:
        def warning(self, *_args, **_kwargs) -> None:
            return None

    module.logger = _Logger()
    sys.modules["loguru"] = module


def _install_fake_system_config(return_value: str | None) -> None:
    app_module = sys.modules.get("app") or types.ModuleType("app")
    models_module = sys.modules.get("app.models") or types.ModuleType("app.models")
    system_config_module = types.ModuleType("app.models.system_config")

    class SystemConfig:
        @classmethod
        async def get_value(cls, _key: str, default: str = "") -> str:
            return default if return_value is None else return_value

        @classmethod
        async def get_all_as_dict(cls) -> dict:
            # 返回模拟配置值，_default_enabled_getter 会读取 im_call_trace_enabled
            return {"im_call_trace_enabled": str(return_value) if return_value is not None else ""}

    system_config_module.SystemConfig = SystemConfig
    sys.modules["app"] = app_module
    sys.modules["app.models"] = models_module
    sys.modules["app.models.system_config"] = system_config_module


def _load_module():
    _install_fake_loguru()
    module_path = (
        Path(__file__).resolve().parents[1] / "app" / "services" / "call_trace_service.py"
    )
    spec = importlib.util.spec_from_file_location("call_trace_service_defaults_test", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load call_trace_service module for test")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CallTraceDefaultsTests(unittest.TestCase):
    def test_default_enabled_getter_returns_true_when_config_missing(self) -> None:
        module = _load_module()
        _install_fake_system_config(return_value=None)

        service = module.CallTraceService()
        self.assertTrue(asyncio.run(service._default_enabled_getter()))

    def test_default_enabled_getter_returns_false_when_config_zero(self) -> None:
        module = _load_module()
        _install_fake_system_config(return_value="0")

        service = module.CallTraceService()
        self.assertFalse(asyncio.run(service._default_enabled_getter()))
