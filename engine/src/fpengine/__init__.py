"""Font Playground engine: read faces, plan and forge merged fonts."""

from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("fpengine")
except PackageNotFoundError:  # A source tree that is not installed.
    __version__ = "0+unknown"
