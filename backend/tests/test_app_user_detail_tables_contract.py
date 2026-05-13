from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
APP_USER_VIEW = REPO_ROOT / "backend" / "web" / "src" / "views" / "operation" / "app-user" / "index.vue"


def _data_table_block(source: str, marker: str) -> str:
    marker_index = source.index(marker)
    table_start = source.rindex("<NDataTable", 0, marker_index)
    table_end = source.index("/>", marker_index) + 2
    return source[table_start:table_end]


def test_app_user_detail_server_paginated_tables_enable_remote_mode():
    source = APP_USER_VIEW.read_text(encoding="utf-8")

    call_record_table = _data_table_block(source, ':data="callRecordRows"')
    bill_table = _data_table_block(source, ':data="billRows"')

    assert ':remote="true"' in call_record_table
    assert ':remote="true"' in bill_table
