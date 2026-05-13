from datetime import date

BIRTH_DATE_MIN = date(1975, 1, 1)
HEIGHT_CM_MIN = 130
HEIGHT_CM_MAX = 230
WEIGHT_KG_MIN = 30
WEIGHT_KG_MAX = 130


def normalize_birth_date(value: date | None) -> date | str | None:
    if value is None:
        return None
    if value < BIRTH_DATE_MIN:
        return "出生日期不能早于1975-01-01"
    if value > date.today():
        return "出生日期不能晚于今天"
    return value


def normalize_height_cm(value: int | None) -> int | str | None:
    if value is None:
        return None
    if value < HEIGHT_CM_MIN or value > HEIGHT_CM_MAX:
        return "身高不合法"
    return value


def normalize_weight_kg(value: int | None) -> int | str | None:
    if value is None:
        return None
    if value < WEIGHT_KG_MIN or value > WEIGHT_KG_MAX:
        return "体重不合法"
    return value
