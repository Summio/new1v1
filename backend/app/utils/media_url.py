from urllib.parse import urlsplit


def to_relative_media_url(value: str | None) -> str:
    if value is None:
        return ""
    text = str(value).strip()
    if not text:
        return ""

    if text.startswith("/uploads/"):
        return text

    parsed = urlsplit(text)
    candidate = parsed.path or ""
    if candidate.startswith("/uploads/"):
        if parsed.query:
            return f"{candidate}?{parsed.query}"
        return candidate

    idx = text.find("/uploads/")
    if idx >= 0:
        return text[idx:]

    return text


def normalize_media_list(value) -> list[str]:
    if not isinstance(value, list):
        return []
    out: list[str] = []
    seen: set[str] = set()
    for item in value:
        if not isinstance(item, str):
            continue
        normalized = to_relative_media_url(item)
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        out.append(normalized)
    return out
