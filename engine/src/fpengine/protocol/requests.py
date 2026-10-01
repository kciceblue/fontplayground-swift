"""Validate request structure without loading a schema library in the helper."""

from __future__ import annotations

import json
import logging
import math
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from typing import BinaryIO

from fpengine.protocol import MAX_REQUEST_BYTES


class RequestError(Exception):
    pass


@dataclass(frozen=True)
class HelloRequest:
    pass


@dataclass(frozen=True)
class ScanRequest:
    files: tuple[str, ...]


@dataclass(frozen=True)
class Expect:
    postscript_name: str | None
    size: int
    mtime: float


@dataclass(frozen=True)
class MaterialRequest:
    path: str
    index: int
    weight: int | None = None
    scale: float | None = None
    expect: Expect | None = None


@dataclass(frozen=True)
class ForgeRequestData:
    materials: tuple[MaterialRequest, ...]
    base_index: int = 0
    script_rules: Mapping[str, int | None] = field(default_factory=dict)
    default_weight: int | None = None
    default_scale: float = 1.0
    family_name: str = "Forged"
    style_name: str = "Regular"
    output_path: str = ""


def _reject(value: str) -> None:
    raise RequestError("Request is not valid JSON: NaN and Infinity are not allowed.")


def read_request(stream: BinaryIO, *, allow_empty: bool) -> dict:
    raw = stream.read(MAX_REQUEST_BYTES + 1)
    if len(raw) > MAX_REQUEST_BYTES:
        raise RequestError("Request is too large (over 64 MiB).")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise RequestError("Request is not UTF-8.") from exc
    if allow_empty and not text.strip():
        return {}
    try:
        obj = json.loads(text, parse_constant=_reject)
    except json.JSONDecodeError as exc:
        raise RequestError(f"Request is not valid JSON: {exc.msg} (line {exc.lineno}, column {exc.colno}).") from exc
    if not isinstance(obj, dict):
        raise RequestError("Request must be a JSON object.")
    return obj


def _fail(pointer: str, problem: str) -> None:
    raise RequestError(f"Invalid request: {pointer}: {problem}.")


def _string(value: object, pointer: str) -> str:
    if not isinstance(value, str):
        _fail(pointer, "must be a string")
    try:
        value.encode("utf-8")
    except UnicodeEncodeError:
        _fail(pointer, "contains an invalid Unicode escape")
    return value


def _path(value: object, pointer: str) -> str:
    value = _string(value, pointer)
    if not value.startswith("/") or len(value) < 2:
        _fail(pointer, "must be an absolute path")
    if ".." in value.split("/"):
        _fail(pointer, "must not contain '..'")
    return value


def _number(value: object, pointer: str) -> float:
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or isinstance(value, float)
        and not math.isfinite(value)
    ):
        _fail(pointer, "must be a number")
    return value


def _integer(value: object, pointer: str) -> int:
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or isinstance(value, float)
        and not math.isfinite(value)
        or int(value) != value
    ):
        _fail(pointer, "must be an integer")
    return int(value)


def _nonnegative(value: object, pointer: str) -> int:
    try:
        value = _integer(value, pointer)
    except RequestError:
        _fail(pointer, "must be a non-negative integer")
    if value < 0:
        _fail(pointer, "must be a non-negative integer")
    return value


def _nullable(parser: Callable) -> Callable:
    return lambda value, pointer: None if value is None else parser(value, pointer)


def _object(value: object, pointer: str, parsers: dict[str, Callable], required: tuple[str, ...] = ()) -> dict:
    if not isinstance(value, dict):
        _fail(pointer, "must be an object")
    prefix = f"{pointer}." if pointer else ""
    for key in required:
        if key not in value:
            _fail(prefix + key, "is required")
    result = {}
    for key, item in value.items():
        if key in parsers:
            result[key] = parsers[key](item, prefix + key)
        else:
            logging.getLogger(__name__).debug("Ignoring unknown request key %s%s", prefix, key)
    return result


def _list(value: object, pointer: str, parser: Callable, *, max_items: int | None = None) -> tuple:
    if not isinstance(value, list):
        _fail(pointer, "must be a list")
    if max_items is not None and len(value) > max_items:
        _fail(pointer, f"must have at most {max_items} items")
    return tuple(parser(item, f"{pointer}[{i}]") for i, item in enumerate(value))


def parse_hello(obj: dict) -> HelloRequest:
    _object(obj, "", {})
    return HelloRequest()


def parse_scan(obj: dict) -> ScanRequest:
    return ScanRequest(**_object(obj, "", {"files": lambda v, p: _list(v, p, _path, max_items=100000)}, ("files",)))


def _expect(value: object, pointer: str) -> Expect:
    return Expect(
        **_object(
            value,
            pointer,
            {
                "postscript_name": _nullable(_string),
                "size": _nonnegative,
                "mtime": _number,
            },
            ("postscript_name", "size", "mtime"),
        )
    )


def _material(value: object, pointer: str) -> MaterialRequest:
    return MaterialRequest(
        **_object(
            value,
            pointer,
            {
                "path": _path,
                "index": _nonnegative,
                "weight": _nullable(_integer),
                "scale": _nullable(_number),
                "expect": _expect,
            },
            ("path", "index"),
        )
    )


def _rules(value: object, pointer: str) -> dict:
    from fpengine.scripts import GROUP_IDS

    if not isinstance(value, dict):
        _fail(pointer, "must be an object")
    result = {}
    for key, item in value.items():
        if key not in GROUP_IDS:
            _fail(f"{pointer}.{key}", "is not a script group")
        result[key] = _nullable(_integer)(item, f"{pointer}.{key}")
    return result


def parse_forge(obj: dict) -> ForgeRequestData:
    def spec(value: object, pointer: str) -> dict:
        return _object(
            value,
            pointer,
            {
                "materials": lambda v, p: _list(v, p, _material),
                "base_index": _integer,
                "script_rules": _rules,
                "default_weight": _nullable(_integer),
                "default_scale": _number,
                "family_name": _string,
                "style_name": _string,
            },
            ("materials",),
        )

    result = _object(obj, "", {"spec": spec, "output_path": _path}, ("spec", "output_path"))
    return ForgeRequestData(**result["spec"], output_path=result["output_path"])
