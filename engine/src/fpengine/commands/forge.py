"""Validate every material, then publish a verified font with one atomic rename."""

import logging
import os
from time import monotonic

from fpengine.face import FontFace, read_face
from fpengine.forge import forge
from fpengine.protocol import cancel
from fpengine.protocol.errors import ErrorCode, HelperError, Stage, map_forge_error
from fpengine.protocol.events import EventWriter
from fpengine.protocol.report import forge_report, read_output_names
from fpengine.protocol.requests import ForgeRequestData, MaterialRequest
from fpengine.protocol.rundir import close_run_dir, open_run_dir, partial_path
from fpengine.spec import ForgeError, ForgeSpec, MaterialSpec


class ForgeProgress:
    def __init__(self, out: EventWriter, n: int):
        self.out, self.n = out, n
        self.stage, self.material_index = "validate", None
        self._next_prepare, self._fraction = 0, 0.0
        self.engine_done = False

    def __call__(self, engine_stage: str, fraction: float) -> None:
        cancel.checkpoint()
        extra = {}
        if engine_stage.startswith("prepare"):
            if self._next_prepare >= self.n:
                logging.getLogger(__name__).warning("More prepare events than materials; clamping the index")
            self.material_index = min(self._next_prepare, self.n - 1)
            self._next_prepare += 1
            stage = "prepare"
            extra["material_index"] = self.material_index
        elif engine_stage in ("plan", "merge", "finish", "verify"):
            stage, self.material_index = engine_stage, None
        elif engine_stage == "done":
            self.engine_done = True
            return
        else:
            logging.getLogger(__name__).debug("Ignoring engine stage %s", engine_stage)
            return
        self.stage = stage
        self._fraction = max(self._fraction, round(min(1.0, max(0.0, fraction)), 4))
        self.out.emit("progress", stage=stage, fraction=self._fraction, **extra)


def _check_output(req: ForgeRequestData) -> None:
    if os.path.isdir(req.output_path):
        raise HelperError(ErrorCode.BAD_REQUEST, None, None, "Invalid request: output_path: is a folder.")
    for material in req.materials:
        same = req.output_path == material.path
        if not same:
            try:
                same = os.path.samefile(req.output_path, material.path)
            except OSError:
                pass
        if same:
            raise HelperError(
                ErrorCode.BAD_REQUEST, None, None, f"The output file is one of the materials: {req.output_path}."
            )


def _load_material(i: int, material: MaterialRequest) -> FontFace:
    path, expected = material.path, material.expect

    def error(code: ErrorCode, message: str) -> HelperError:
        return HelperError(code, None if code == ErrorCode.BAD_REQUEST else Stage.VALIDATE, i, message)

    try:
        st = os.stat(path)
    except FileNotFoundError as exc:
        raise error(
            ErrorCode.STALE_MATERIAL if expected else ErrorCode.IO_ERROR,
            f"{path}: the font file is no longer there.",
        ) from exc
    except OSError as exc:
        raise error(ErrorCode.IO_ERROR, f"Can't read {path} ({exc.strerror or exc}).") from exc
    if expected and st.st_size != expected.size:
        raise error(
            ErrorCode.STALE_MATERIAL, f"{path} changed since it was scanned (size {expected.size} → {st.st_size})."
        )
    if expected and abs(st.st_mtime - expected.mtime) > 1e-3:
        raise error(
            ErrorCode.STALE_MATERIAL,
            f"{path} changed since it was scanned (modified {expected.mtime:.3f} → {st.st_mtime:.3f}).",
        )
    try:
        face = read_face(path, material.index)
    except IndexError as exc:
        if expected:
            raise error(ErrorCode.STALE_MATERIAL, f"{path} has no face {material.index} any more.") from exc
        raise error(
            ErrorCode.BAD_REQUEST, f"Invalid request: spec.materials[{i}].index: {path} has {exc.args[0]} faces."
        ) from exc
    except OSError as exc:
        raise error(ErrorCode.IO_ERROR, f"Can't read {path} ({exc.strerror or exc}).") from exc
    except Exception as exc:
        raise error(
            ErrorCode.UNSUPPORTED_FONT, f"{path} can't be read as a font ({type(exc).__name__}: {exc})."
        ) from exc
    if expected and face.postscript_name != expected.postscript_name:
        raise error(
            ErrorCode.STALE_MATERIAL,
            f"{path} face {material.index} is now '{face.postscript_name}', not '{expected.postscript_name}'.",
        )
    if not face.supported:
        raise error(ErrorCode.UNSUPPORTED_FONT, f"{face.display_name}: {face.unsupported_reason}")
    return face


def _fsync(path: str, *, directory: bool = False) -> None:
    fd = os.open(path, os.O_RDONLY | (getattr(os, "O_DIRECTORY", 0) if directory else 0))
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _add_report_warning(report: dict, code: str, note: str) -> None:
    report["issues"].append(
        {"code": code, "severity": "warning", "material_index": None, "group": None, "message": note}
    )
    report["warnings"].append(note)


def run(req: ForgeRequestData, out: EventWriter) -> int:
    started = monotonic()
    out.emit("progress", stage="validate", fraction=0.0)
    _check_output(req)
    directory = os.path.dirname(req.output_path)
    try:
        os.makedirs(directory, exist_ok=True)
    except OSError as exc:
        raise HelperError(
            ErrorCode.IO_ERROR, Stage.VALIDATE, None, f"Can't write {directory} ({exc.strerror or exc})."
        ) from exc
    faces = [_load_material(i, material) for i, material in enumerate(req.materials)]
    spec = ForgeSpec(
        materials=[MaterialSpec(face, material.weight, material.scale) for face, material in zip(faces, req.materials)],
        base_index=req.base_index,
        script_rules=dict(req.script_rules),
        default_weight=req.default_weight,
        default_scale=req.default_scale,
        family_name=req.family_name,
        style_name=req.style_name,
    )
    if problems := spec.validate():
        raise HelperError(ErrorCode.VALIDATE, Stage.VALIDATE, None, " ".join(problems))
    run_dir, partial = None, None
    progress = ForgeProgress(out, len(faces))
    try:
        # Defer a signal until the finally block owns both cleanup paths.
        with cancel.critical():
            run_dir = open_run_dir()
            partial = partial_path(req.output_path)
        try:
            engine_report = forge(spec, partial, progress=progress)
        except ForgeError as exc:
            raise map_forge_error(exc, progress, faces) from exc
        _fsync(partial)
        names = read_output_names(partial)
        report = forge_report(req, engine_report, names, duration_s=round(monotonic() - started, 3))
        with cancel.critical():
            try:
                os.replace(partial, req.output_path)
            except OSError as exc:
                raise HelperError(
                    ErrorCode.IO_ERROR, Stage.VERIFY, None, f"Can't write {req.output_path} ({exc.strerror or exc})."
                ) from exc
            try:
                _fsync(directory, directory=True)
            except OSError as exc:
                # The rename is the commit point: the previous file is already replaced, so this is a saved result
                # whose durability is unconfirmed, never an error that leaves a newly published font behind.
                logging.getLogger(__name__).warning("Can't sync %s", directory, exc_info=True)
                _add_report_warning(
                    report,
                    "output_sync_failed",
                    f"The font was saved, but its folder couldn't be flushed to disk ({exc.strerror or exc}); "
                    "if the Mac loses power soon, build it again.",
                )
            out.emit("progress", stage="done", fraction=1.0)
            out.terminal("result", command="forge", report=report)
    finally:
        try:
            if partial is not None:
                os.unlink(partial)
        except FileNotFoundError:
            pass
        except OSError:
            logging.getLogger(__name__).warning("Can't remove partial font %s", partial, exc_info=True)
        finally:
            if run_dir is not None:
                close_run_dir(run_dir)
    return 0
