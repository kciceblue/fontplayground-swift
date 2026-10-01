from dataclasses import replace

from fpengine.face import read_face, read_faces
from fpengine.records import FACE_RECORD_KEYS, face_record
from tests.fixtures import build_font, cps


def test_output_framing_utf8_lines(run_helper, tmp_path):
    path = build_font(tmp_path / "Chinese.ttf", "合体测试", "Regular", cps("abc"))
    events, code, _, raw = run_helper("scan", {"files": [str(path)]})
    assert code == 0 and "合体测试".encode() in raw and b"\\u" not in raw
    assert raw.endswith(b"\n")
    assert events[1]["face"]["family"] == "合体测试"


def test_scan_streams_faces_in_request_order(run_helper, font_dir, tmp_path):
    text = tmp_path / "NotAFont.ttf"
    text.write_bytes(b"x" * 75)
    paths = [str(font_dir / "A.ttf"), str(font_dir / "T.ttc"), str(tmp_path / "missing/X.ttf"), str(text)]
    events, code, _, _ = run_helper("scan", {"files": paths})
    assert code == 0
    progress = [e for e in events if e["type"] == "progress"]
    assert [e["done"] for e in progress] == sorted(e["done"] for e in progress)
    assert progress[0]["done"] == 0 and progress[-1]["done"] == 4 and progress[-1]["fraction"] == 1
    middle = [e for e in events if e["type"] not in ("progress", "result")]
    assert [(e["face"]["path"], e["face"]["index"]) for e in middle[:3]] == [
        (paths[0], 0),
        (paths[1], 0),
        (paths[1], 1),
    ]
    assert middle[3]["code"] == "not_found" and middle[3]["message"] == "File not found."
    assert middle[4]["code"] == "unreadable"
    assert middle[4]["message"].startswith("Not a font file fontTools can read (")
    assert events[-1]["summary"] == {"files": 4, "faces": 3, "file_errors": 2, "duplicates": 0}


def test_scan_face_record_matches_reader(run_helper, font_dir, schemas):
    paths = [str(font_dir) + "//" + name for name in ("A.ttf", "B.otf", "T.ttc", "V.ttf")]
    events, _, _, _ = run_helper("scan", {"files": paths})
    faces = [e["face"] for e in events if e["type"] == "face"]
    expected = []
    for path in paths:
        for face in read_faces(path):
            record = face_record(face)
            record["path"] = path
            expected.append(record)
    assert faces == expected
    assert all(list(face) == schemas["face-record.schema.json"]["required"] == list(FACE_RECORD_KEYS) for face in faces)


def test_scan_duplicates_empty_and_directory(run_helper, font_dir):
    path = str(font_dir / "A.ttf")
    events, _, _, _ = run_helper("scan", {"files": [path, path]})
    assert events[-1]["summary"] == {"files": 1, "faces": 1, "file_errors": 0, "duplicates": 1}
    events, _, _, _ = run_helper("scan", {"files": []})
    assert len(events) == 1
    assert events[0]["summary"] == {"files": 0, "faces": 0, "file_errors": 0, "duplicates": 0}
    events, _, _, _ = run_helper("scan", {"files": [str(font_dir)]})
    assert events[1]["code"] == "io_error" and events[1]["message"] == "Not a regular file."


def test_scan_output_is_deterministic(run_helper, font_dir):
    request = {"files": [str(font_dir / name) for name in ("A.ttf", "T.ttc", "missing.ttf")]}
    left = run_helper("scan", request)[0]
    right = run_helper("scan", request)[0]
    assert [e for e in left if e["type"] != "progress"] == [e for e in right if e["type"] != "progress"]


def test_scan_serializes_all_faces_before_sending(monkeypatch, inprocess, font_dir):
    from fpengine.commands import scan

    real = scan.face_payload

    def fail_second(face, request_path):
        if face.index == 1:
            raise RuntimeError("bad metadata")
        return real(face, request_path)

    monkeypatch.setattr(scan, "face_payload", fail_second)
    events, code, _ = inprocess("scan", {"files": [str(font_dir / "T.ttc")]})
    assert code == 0 and not any(e["type"] == "face" for e in events)
    assert events[1]["code"] == "internal"


def test_face_payload_repairs_surrogates(font_dir):
    from fpengine.protocol.records import face_payload

    face = replace(read_faces(font_dir / "A.ttf")[0], family="x\ud800", local_names=("x\udc00",))
    record = face_payload(face, "/a//b.ttf")
    assert record["family"] == "x\ufffd" and record["local_names"] == ["x\ufffd"]
    assert record["path"] == "/a//b.ttf"


def test_read_face_only_builds_requested_metadata(font_dir, monkeypatch):
    import fpengine.face as reader

    real, seen = reader._face, []

    def record(font, path, index, *args):
        seen.append(index)
        return real(font, path, index, *args)

    expected = read_faces(font_dir / "T.ttc")[1]
    monkeypatch.setattr(reader, "_face", record)
    assert read_face(font_dir / "T.ttc", 1) == expected
    assert seen == [1]
