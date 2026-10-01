"""Report runtime identity without importing the forge pipeline."""

import importlib.metadata
import platform
import sys

import fontTools

from fpengine import __version__
from fpengine.face import READER_VERSION
from fpengine.protocol import CAPABILITIES
from fpengine.protocol.events import EventWriter
from fpengine.protocol.requests import HelloRequest


def run(req: HelloRequest, out: EventWriter) -> int:
    try:
        import unicodedata2 as unicode_data
    except ImportError:
        import unicodedata as unicode_data
    try:
        version = importlib.metadata.version("fpengine")
    except importlib.metadata.PackageNotFoundError:
        version = __version__
    out.emit(
        "hello",
        fpengine_version=version,
        python=platform.python_version(),
        fonttools=fontTools.version,
        unicode_version=unicode_data.unidata_version,
        platform=f"{sys.platform}-{platform.machine()}",
        capabilities=list(CAPABILITIES),
        face_reader_version=READER_VERSION,
    )
    out.terminal("result", command="hello")
    return 0
