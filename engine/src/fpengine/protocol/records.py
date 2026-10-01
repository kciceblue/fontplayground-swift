"""Preserve source paths while repairing malformed font metadata strings."""

from fpengine.face import FontFace
from fpengine.records import face_record


def clean_strings(value: object) -> object:
    if isinstance(value, str):
        return value.encode("utf-16", "surrogatepass").decode("utf-16", "replace")
    if isinstance(value, dict):
        return {key: clean_strings(item) for key, item in value.items()}
    if isinstance(value, (tuple, list)):
        return [clean_strings(item) for item in value]
    return value


def face_payload(face: FontFace, request_path: str) -> dict:
    record = clean_strings(face_record(face))
    record["path"] = request_path
    return record
