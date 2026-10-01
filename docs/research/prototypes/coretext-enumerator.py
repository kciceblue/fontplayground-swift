"""Prototype: CoreText-backed font enumeration for darwin (scratch only)."""
import time, logging, collections
from pathlib import Path
logging.getLogger("fontTools").setLevel(logging.ERROR)
import CoreText as CT
from fontTools.ttLib import TTCollection, TTFont
from fontplayground.catalog.face import read_faces
from fontplayground.paths import is_font_file
from fontplayground.ui.languages import language, covers_well

def coretext_font_files():
    """(files, visible_ps): every font file CoreText has registered, and the PostScript names it shows in menus."""
    urls = CT.CTFontManagerCopyAvailableFontURLs() or []
    files = sorted({u.path() for u in urls if u.isFileURL()})
    visible = set(CT.CTFontManagerCopyAvailablePostScriptNames() or [])
    return files, visible

def ps_names(path):
    p = str(path)
    if p.lower().endswith((".ttc", ".otc")):
        coll = TTCollection(p, lazy=True)
        try: return [f["name"].getDebugName(6) for f in coll.fonts]
        finally: coll.close()
    f = TTFont(p, lazy=True)
    try: return [f["name"].getDebugName(6)]
    finally: f.close()

t = time.perf_counter()
files, visible = coretext_font_files()
t_enum = time.perf_counter() - t
print("CT enumeration: %d files, %d visible PS names in %.3fs" % (len(files), len(visible), t_enum))
skipped = [f for f in files if not is_font_file(Path(f))]
print("files the extension filter would drop:", skipped)
t = time.perf_counter()
faces, hidden, failed = [], [], []
for f in files:
    try:
        fs = read_faces(f); ps = ps_names(f)
    except Exception as e:
        failed.append((f, repr(e))); continue
    for face, name in zip(fs, ps):
        (faces if (name in visible and not face.family.startswith('.')) else hidden).append(face)
print("read in %.2fs: visible faces=%d hidden faces=%d failed=%d" % (time.perf_counter()-t, len(faces), len(hidden), len(failed)))
for f,e in failed: print("  FAIL", f, e[:100])
print("visible families:", len({f.family for f in faces}))
print("hidden families sample:", sorted({f.family for f in hidden})[:30])
for lid in ("chinese_s", "chinese_t", "japanese", "korean"):
    print(lid, sorted({f.family for f in faces if f.supported and covers_well(f, language(lid))}))
