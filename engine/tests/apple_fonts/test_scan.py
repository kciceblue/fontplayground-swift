import pytest

from tests.apple_fonts.locate import SEARCH_ROOTS
from tests.apple_fonts.runner import run_helper

pytestmark = [pytest.mark.apple_fonts, pytest.mark.macos, pytest.mark.slow]


def test_real_face_metadata(tmp_path):
    names = ("GeezaPro.ttc", "SFNS.ttf", "LastResort.otf", "Courier.ttc", "Damascus.ttc")
    files = []
    for name in names:
        path = next((root / name for root in SEARCH_ROOTS if (root / name).is_file()), None)
        if path is None:
            pytest.skip(f"not installed: {name}")
        files.append(str(path))
    run = run_helper("scan", {"files": files}, tmpdir=tmp_path, timeout_s=60)
    assert run.returncode == 0 and not run.timed_out, run.stderr_tail
    assert sum(event["type"] in {"result", "error"} for event in run.events) == 1
    faces = [event["face"] for event in run.events if event["type"] == "face"]
    assert run.result["faces"] == len(faces) and run.result["file_errors"] == 0
    assert run.result["files"] == len(files)
    for face in faces:
        if face["postscript_name"] == "GeezaPro":
            assert face["family"] == "Geeza Pro" and face["aat"]["morx"]
            assert "arabic" not in face["shapes_groups"]
        elif face["path"] == files[1]:
            assert face["hidden"]
        elif face["path"] == files[2]:
            assert face["suspicious_coverage"]
        elif face["postscript_name"] == "Damascus":
            assert face["family"] == "Damascus" and "arabic" in face["shapes_groups"]
    assert {"GeezaPro", "Damascus"} <= {face["postscript_name"] for face in faces}
    couriers = [face for face in faces if face["path"] == files[3]]
    assert len(couriers) == 4 and all(not face["has_os2"] for face in couriers)
    assert next(face for face in couriers if face["postscript_name"] == "Courier-Bold")["weight_class"] == 700
    assert set(face["path"] for face in faces) == set(files)
