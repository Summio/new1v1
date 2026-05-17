import ast
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = BACKEND_ROOT / "app"
TIME_UTILS = APP_ROOT / "core" / "time_utils.py"


def test_backend_datetime_now_calls_stay_inside_time_utils() -> None:
    offenders: list[str] = []
    for path in sorted(APP_ROOT.rglob("*.py")):
        if path == TIME_UTILS:
            continue
        text = path.read_text(encoding="utf-8")
        tree = ast.parse(text, filename=str(path))
        datetime_class_aliases = {"datetime"}
        datetime_module_aliases: set[str] = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) and node.module == "datetime":
                for alias in node.names:
                    if alias.name == "datetime":
                        datetime_class_aliases.add(alias.asname or alias.name)
            elif isinstance(node, ast.Import):
                for alias in node.names:
                    if alias.name == "datetime":
                        datetime_module_aliases.add(alias.asname or alias.name)

        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            func = node.func
            if (
                isinstance(func, ast.Attribute)
                and func.attr in {"now", "utcnow"}
                and isinstance(func.value, ast.Name)
                and func.value.id in datetime_class_aliases
            ):
                offenders.append(f"{path.relative_to(BACKEND_ROOT)}:{node.lineno}")
            elif (
                isinstance(func, ast.Attribute)
                and func.attr in {"now", "utcnow"}
                and isinstance(func.value, ast.Attribute)
                and func.value.attr == "datetime"
                and isinstance(func.value.value, ast.Name)
                and func.value.value.id in datetime_module_aliases
            ):
                offenders.append(f"{path.relative_to(BACKEND_ROOT)}:{node.lineno}")

    assert offenders == []
