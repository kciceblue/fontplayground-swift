"""Stream one file at a time so a catalog scan does not retain every font."""

import os
import stat
from time import monotonic

from fpengine.face import read_faces
from fpengine.protocol import cancel
from fpengine.protocol.events import EventWriter
from fpengine.protocol.records import face_payload
from fpengine.protocol.requests import ScanRequest


class _NotRegular(Exception):
    pass


def run(req: ScanRequest, out: EventWriter) -> int:
    files = list(dict.fromkeys(req.files))
    n, faces_sent, errors = len(files), 0, 0

    def file_error(path: str, code: str, message: str) -> None:
        nonlocal errors
        out.emit("file_error", path=path, code=code, message=message)
        errors += 1

    if n:
        out.emit("progress", stage="scan", fraction=0.0, done=0, total=n)
    last = monotonic()
    for k, path in enumerate(files, 1):
        cancel.checkpoint()
        faces = records = None
        try:
            if not stat.S_ISREG(os.stat(path).st_mode):
                raise _NotRegular
            faces = read_faces(path)
        except _NotRegular:
            file_error(path, "io_error", "Not a regular file.")
        except FileNotFoundError:
            file_error(path, "not_found", "File not found.")
        except OSError as exc:
            file_error(path, "io_error", f"Can't read this file ({exc.strerror or exc}).")
        except Exception as exc:
            file_error(path, "unreadable", f"Not a font file fontTools can read ({type(exc).__name__}: {exc}).")
        else:
            try:
                records = [face_payload(face, request_path=path) for face in faces]
            except Exception as exc:
                file_error(path, "internal", f"Unexpected error while reading this file ({type(exc).__name__}: {exc}).")
            else:
                for record in records:
                    out.emit("face", face=record)
                    faces_sent += 1
        faces = records = None
        if k == n or monotonic() - last >= 0.25:
            out.emit("progress", stage="scan", fraction=round(k / n, 4), done=k, total=n)
            last = monotonic()
    out.terminal(
        "result",
        command="scan",
        summary={
            "files": n,
            "faces": faces_sent,
            "file_errors": errors,
            "duplicates": len(req.files) - n,
        },
    )
    return 0
