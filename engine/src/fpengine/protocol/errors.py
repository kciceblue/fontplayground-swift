"""Stable wire errors separate actionable failures from implementation bugs."""

from enum import StrEnum
from traceback import format_exception
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Sequence

    from fpengine.commands.forge import ForgeProgress
    from fpengine.face import FontFace
    from fpengine.spec import ForgeError


class ErrorCode(StrEnum):
    BAD_REQUEST = "bad_request"
    VALIDATE = "validate"
    STALE_MATERIAL = "stale_material"
    UNSUPPORTED_FONT = "unsupported_font"
    AAT_UNSUPPORTED_SCRIPT = "aat_unsupported_script"
    GLYPH_LIMIT = "glyph_limit"
    PREPARE_FAILED = "prepare_failed"
    MERGE_FAILED = "merge_failed"
    FINISH_FAILED = "finish_failed"
    VERIFY_FAILED = "verify_failed"
    IO_ERROR = "io_error"
    INTERNAL = "internal"


class FileErrorCode(StrEnum):
    NOT_FOUND = "not_found"
    IO_ERROR = "io_error"
    UNREADABLE = "unreadable"
    INTERNAL = "internal"


class Stage(StrEnum):
    VALIDATE = "validate"
    PLAN = "plan"
    PREPARE = "prepare"
    MERGE = "merge"
    FINISH = "finish"
    VERIFY = "verify"
    DONE = "done"
    SCAN = "scan"


EXIT_OK, EXIT_BAD_REQUEST, EXIT_ERROR = 0, 2, 3
EXIT_SIGINT, EXIT_CLIENT_GONE, EXIT_SIGTERM = 130, 141, 143


class HelperError(Exception):
    def __init__(
        self, code: ErrorCode, stage: Stage | None, material_index: int | None, message: str, detail: str | None = None
    ):
        self.code, self.stage, self.material_index = code, stage, material_index
        self.message, self.detail = message, detail
        super().__init__(message)


def map_forge_error(err: "ForgeError", progress: "ForgeProgress", faces: "Sequence[FontFace]") -> HelperError:
    try:
        code = ErrorCode(getattr(err, "code", None))
    except (ValueError, TypeError):
        code = {
            "validate": ErrorCode.VALIDATE,
            "prepare": ErrorCode.PREPARE_FAILED,
            "merge": ErrorCode.MERGE_FAILED,
            "finish": ErrorCode.FINISH_FAILED,
            "verify": ErrorCode.VERIFY_FAILED,
        }.get(err.stage, ErrorCode.INTERNAL)
        if err.stage == "finish" and isinstance(err.__cause__, OSError):
            code = ErrorCode.IO_ERROR
    stage = err.stage if err.stage in Stage else progress.stage
    stage = Stage.VERIFY if stage == Stage.DONE else stage
    index = getattr(err, "material_index", None)
    if index is None and err.stage == "prepare":
        index = progress.material_index
    if index is None and err.material:
        matches = [i for i, face in enumerate(faces) if face.display_name == err.material]
        if len(matches) == 1:
            index = matches[0]
    return HelperError(code, stage, index, err.message, "".join(format_exception(err)))
