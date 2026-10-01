"""Process boundary for the font engine; imports here must remain stdlib-only."""

import importlib
import importlib.metadata
import logging
import os
import platform
import signal
import sys
import time
import traceback
import warnings
from collections.abc import Callable
from typing import BinaryIO

from fpengine.protocol import cancel, watchdog
from fpengine.protocol.errors import EXIT_CLIENT_GONE, EXIT_SIGINT, EXIT_SIGTERM, ErrorCode, HelperError
from fpengine.protocol.events import EventSerializationError, EventWriter
from fpengine.protocol.requests import RequestError, parse_forge, parse_hello, parse_scan, read_request


def configure_logging() -> Callable[[], None]:
    root = logging.getLogger()
    engine, fonttools = logging.getLogger("fpengine"), logging.getLogger("fontTools")
    old_handlers, old_levels = root.handlers[:], (root.level, engine.level, fonttools.level)
    old_warning = warnings.showwarning
    warnings_were_captured = getattr(logging, "_warnings_showwarning", None) is not None
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(logging.Formatter("%(asctime)s fpengine[%(process)d] %(levelname)s %(name)s: %(message)s"))
    root.handlers = [handler]
    root.setLevel(logging.WARNING)
    level = {"debug": logging.DEBUG, "info": logging.INFO, "warning": logging.WARNING}.get(
        os.environ.get("FPENGINE_LOG", "info").lower(), logging.INFO
    )
    engine.setLevel(level)
    fonttools.setLevel(logging.WARNING if level == logging.DEBUG else logging.ERROR)
    logging.captureWarnings(True)

    def restore() -> None:
        if not warnings_were_captured:
            logging.captureWarnings(False)
        warnings.showwarning = old_warning
        root.handlers = old_handlers
        for logger, previous in zip((root, engine, fonttools), old_levels):
            logger.setLevel(previous)
        handler.close()

    return restore


def _silence_closed_stdout(stream: BinaryIO) -> None:
    try:
        fd = stream.fileno()
        null = os.open(os.devnull, os.O_WRONLY)
        try:
            os.dup2(null, fd)
        finally:
            os.close(null)
    except (OSError, ValueError, AttributeError):
        pass


def main(argv: list[str] | None = None, *, stdin: BinaryIO | None = None, stdout: BinaryIO | None = None) -> int:
    out_stream = sys.stdout.buffer if stdout is None else stdout
    saved_stdout = sys.stdout
    out = EventWriter(out_stream)
    logger = logging.getLogger("fpengine.cli")
    command, code, started = "request", 3, time.monotonic()
    restore: Callable[[], None] | None = None
    restore_logging: Callable[[], None] | None = None
    try:
        # Everything after the handlers exist runs inside this guard, so a SIGTERM during startup still exits 143
        # and restores stdout and the previous handlers.
        restore = cancel.install()
        sys.stdout = sys.stderr
        if hasattr(sys.stderr, "reconfigure"):
            sys.stderr.reconfigure(encoding="utf-8", errors="backslashreplace")
        restore_logging = configure_logging()
        cancel.checkpoint()
        if stdin is None and stdout is None:
            watchdog.start_parent_watchdog()
        try:
            args = sys.argv[1:] if argv is None else argv
            if not args:
                raise RequestError("No command given. Use hello, scan or forge.")
            if len(args) > 1:
                raise RequestError(f"Unexpected arguments: {' '.join(args[1:])}")
            command = args[0]
            if command in ("-h", "--help", "--version"):
                from fpengine import __version__

                text = f"fpengine {__version__}\n" if command == "--version" else "Usage: fpengine hello|scan|forge\n"
                out_stream.write(text.encode())
                out_stream.flush()
                code = 0
                return code
            if command not in ("hello", "scan", "forge"):
                raise RequestError(f"Unknown command '{command}'. Use hello, scan or forge.")
            logger.info(
                "start %s python=%s fonttools=%s",
                command,
                platform.python_version(),
                importlib.metadata.version("fonttools"),
            )
            obj = read_request(sys.stdin.buffer if stdin is None else stdin, allow_empty=command == "hello")
            req = {"hello": parse_hello, "scan": parse_scan, "forge": parse_forge}[command](obj)
            module = importlib.import_module(f"fpengine.commands.{command}")
            code = module.run(req, out)
        except EventSerializationError:
            code = 3
        except RequestError as exc:
            out.terminal("error", code="bad_request", stage=None, material_index=None, message=str(exc), detail=None)
            code = 2
        except HelperError as exc:
            out.terminal(
                "error",
                code=exc.code,
                stage=exc.stage,
                material_index=exc.material_index,
                message=exc.message,
                detail=exc.detail,
            )
            code = 2 if exc.code == ErrorCode.BAD_REQUEST else 3
        except Exception as exc:
            logger.exception("Unexpected error")
            if not out.terminal_sent:
                out.terminal(
                    "error",
                    code="internal",
                    stage="verify" if out.last_stage == "done" else out.last_stage,
                    material_index=None,
                    message=f"Unexpected error: {type(exc).__name__}: {exc}",
                    detail="".join(traceback.format_exception(exc)),
                )
            code = 3
    except cancel.ClientGone:
        _silence_closed_stdout(out_stream)
        code = EXIT_CLIENT_GONE
    except cancel.Cancelled as exc:
        logger.info("cancelled by %s during %s", signal.Signals(exc.signum).name, out.last_stage)
        code = EXIT_SIGINT if exc.signum == signal.SIGINT else EXIT_SIGTERM
    finally:
        logger.info("finished %s in %.2fs exit=%s", command, time.monotonic() - started, code)
        if restore_logging is not None:
            restore_logging()
        sys.stdout = saved_stdout
        if restore is not None:
            restore()
    return code
