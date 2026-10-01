"""Prototype of a headless engine helper for a native (Swift) shell.

Protocol: one JSON request on stdin -> newline-delimited JSON events on stdout.
  request  = ForgeSpec.to_dict() + {"output": "/path/out.ttf"}
  events   = {"event":"progress","stage":..,"fraction":..} ... then
             {"event":"done","report":{...}} | {"event":"error","stage":..,"material":..,"message":..}
Cancellation: the parent sends SIGTERM (or closes stdin); the engine stops at the next stage boundary.
"""
import json, signal, sys, dataclasses

def main() -> int:
    import logging
    logging.getLogger("fontTools").setLevel(logging.ERROR)
    from fontplayground.catalog.face import read_faces
    from fontplayground.engine.forge import forge
    from fontplayground.engine.spec import ForgeError, ForgeSpec
    req = json.load(sys.stdin)
    cancelled = False
    def on_term(*_):
        nonlocal cancelled
        cancelled = True
    signal.signal(signal.SIGTERM, on_term)
    def emit(obj):
        sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n"); sys.stdout.flush()
    faces = {}
    for m in req["materials"]:
        for f in read_faces(m["path"]):
            faces[f.key] = f
    spec = ForgeSpec.from_dict(req, faces)
    def progress(stage, fraction):
        if cancelled:
            raise ForgeError("cancelled", None, "cancelled")
        emit({"event": "progress", "stage": stage, "fraction": fraction})
    try:
        rep = forge(spec, req["output"], progress=progress)
    except ForgeError as e:
        emit({"event": "error", "stage": e.stage, "material": e.material, "message": e.message})
        return 2
    emit({"event": "done", "report": dataclasses.asdict(rep)})
    return 0

if __name__ == "__main__":
    sys.exit(main())
