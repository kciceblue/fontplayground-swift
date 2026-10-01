"""Versioned helper transport; no optional runtime dependencies."""

PROTOCOL_VERSION = 1
CAPABILITIES = ("hello", "scan", "forge", "forge.expect")
MAX_REQUEST_BYTES = 64 * 1024 * 1024
