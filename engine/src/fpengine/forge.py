"""Orchestrate a forge run: validate -> plan -> prepare -> merge -> finish -> verify."""

from __future__ import annotations

import tempfile
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path

from fontTools.ttLib import TTFont

from fpengine import merge as M
from fpengine.licence import EMBEDDING_NOTES, FS_LABELS, LICENCE_NOTES, NOTICE_IDS, OPEN_NOTE, output_fs_type
from fpengine.naming import ForgeStamp, clean_name, new_stamp, postscript_name
from fpengine.planner import plan, source_of
from fpengine.prepare import PreparedFont, prepare
from fpengine.scripts import GROUP_IDS, groups_covered
from fpengine.shaping import SCRIPT_SHAPING, explain_unshaped, join_names, responsible_scripts, rule_errors
from fpengine.spec import ForgeError, ForgeReport, ForgeSpec, Issue, LicenceNote, MaterialReport, Plan

ProgressFn = Callable[[str, float], None]
_AAT_NOTES = {
    "morx": (
        "aat_morx_dropped",
        "Apple-only (AAT) ligatures and alternates are not carried over; the forged font uses plain letter forms",
    ),
    "kerning": ("aat_kerning_dropped", "Apple-only (AAT) kerning is not carried over"),
    "tracking": (
        "aat_tracking_dropped",
        "Apple tracking (trak) is not carried over; spacing can differ from the original at some sizes",
    ),
}


def _shaping_issues(spec: ForgeSpec, p: Plan, prepared: list[PreparedFont]) -> list[Issue]:
    issues = []
    raw_sets = [material.face.codepoints for material in spec.materials]
    for i, (material, pf) in enumerate(zip(spec.materials, prepared)):
        face = material.face
        if p.assignments[i]:
            for loss, (code, note) in _AAT_NOTES.items():
                if loss in pf.aat_losses:
                    issues.append(Issue(code, "warning", i, None, f"{face.display_name}: {note}"))
        would = {cp for cp in face.unshaped if source_of(cp, raw_sets, spec.script_rules) == i}
        if not would:
            continue
        explanation = explain_unshaped(face.codepoints, face.ot_gsub, face.ot_gpos)
        for group in GROUP_IDS:
            affected = {cp: explanation[cp] for cp in would if SCRIPT_SHAPING[explanation[cp]].group == group}
            if not affected:
                continue
            names = join_names(SCRIPT_SHAPING[code].name for code in responsible_scripts(affected))
            drawn = len(affected.keys() & p.source.keys())
            reason = (
                "shapes them with Apple-only rules (AAT) that can't be carried over"
                if face.aat_morx
                else "has no OpenType shaping rules for them"
            )
            note = (
                f"{names} characters are drawn by other fonts or left out "
                f"({drawn} drawn by other fonts, {len(affected) - drawn} left out): this font {reason}"
            )
            issues.append(Issue("unshaped_left_out", "warning", i, group, f"{face.display_name}: {note}"))
    return issues


def _licence_classes(face) -> tuple[str, ...]:
    return face.licence_classes or (face.licence_class,)


def _licence_summary(spec: ForgeSpec, p: Plan) -> tuple[int, list[LicenceNote], str | None]:
    contributors = [i for i in range(len(spec.materials)) if p.assignments[i]]
    fs_type = output_fs_type(spec.materials[i].face.fs_type for i in contributors)
    notes = []
    for licence_class, text in LICENCE_NOTES.items():
        indexes = tuple(i for i in contributors if licence_class in _licence_classes(spec.materials[i].face))
        if indexes:
            notes.append(LicenceNote(licence_class, indexes, text))
    description = " ".join(note.text for note in notes) if notes else (OPEN_NOTE if contributors else None)
    return fs_type, notes, description


def _carried_notices(
    p: Plan, prepared: Sequence[PreparedFont], budget: int
) -> tuple[dict[int, list[str]], dict[int, int]]:
    """Contributing sources' notices, each kept once in material order, and how many each source had left out.

    NOTICE_IDS order decides what stays when `budget` (merge.notice_budget) runs out: copyright notices first.
    """
    kept: dict[int, list[str]] = {name_id: [] for name_id in NOTICE_IDS}
    left_out: dict[int, int] = {}
    for name_id in NOTICE_IDS:
        for i, part in enumerate(prepared):
            if not p.assignments[i]:
                continue
            for notice_id, text in part.notices:
                if notice_id != name_id or text in kept[name_id]:
                    continue
                cost = M.notice_bytes(text)
                if cost > budget:
                    left_out[i] = left_out.get(i, 0) + 1
                    continue
                budget -= cost
                kept[name_id].append(text)
    return kept, left_out


def _report(
    spec: ForgeSpec,
    p: Plan,
    prepared: list[PreparedFont],
    n_cps: int,
    n_glyphs: int,
    out: str,
    forge_issues: Sequence[Issue] = (),
    notices_left_out: Mapping[int, int] | None = None,
) -> ForgeReport:
    notices_left_out = notices_left_out or {}
    materials, warnings = [], []
    issues = [issue for part in prepared for issue in part.issues]
    shaping_issues = _shaping_issues(spec, p, prepared)
    for i, (m, pf) in enumerate(zip(spec.materials, prepared)):
        notes = list(pf.warnings)
        material_issues = [issue for issue in (*forge_issues, *shaping_issues) if issue.material_index == i]
        if p.assignments[i]:
            usage = output_fs_type([m.face.fs_type]) & 0x000E
            if usage:
                code = {2: "restricted", 4: "preview_print", 8: "editable"}[usage]
                material_issues.append(
                    Issue(f"embedding_{code}", "warning", i, None, f"{m.face.display_name}: {EMBEDDING_NOTES[usage]}")
                )
            for licence_class, text in LICENCE_NOTES.items():
                if licence_class in _licence_classes(m.face):
                    code = licence_class.replace("-", "_")
                    material_issues.append(
                        Issue(f"licence_{code}", "warning", i, None, f"{m.face.display_name}: {text}")
                    )
        if i in notices_left_out:
            note = (
                f"copyright and licence notices too long to keep in the forged font ({notices_left_out[i]} left out); "
                "keep the source font's own notices and licence with the forged font"
            )
            material_issues.append(Issue("notices_left_out", "warning", i, None, f"{m.face.display_name}: {note}"))
        notes.extend(
            issue.message.removeprefix(f"{m.face.display_name}: ")
            for issue in material_issues
            if not issue.code.startswith("licence_")
        )
        if not p.assignments[i]:
            notes.append("contributes no characters")
        materials.append(
            MaterialReport(m.face.display_name, len(p.assignments[i]), groups_covered(p.assignments[i]), notes)
        )
        warnings += [f"{m.face.display_name}: {n}" for n in notes]
        issues.extend(material_issues)
    report_issues = [issue for issue in forge_issues if issue.material_index is None]
    fs_type, licence_notes, _ = _licence_summary(spec, p)
    if fs_type:
        note = (
            f"The forged font is marked “{FS_LABELS[fs_type & 0x000E]}” (fsType {fs_type}) "
            "because that is the most restrictive embedding permission of the fonts it uses."
        )
        report_issues.append(Issue("output_fs_type", "warning", None, None, note))
    warnings.extend(issue.message for issue in report_issues)
    issues.extend(report_issues)
    issues.sort(key=lambda issue: (issue.material_index is None, issue.material_index or 0))
    family, style = clean_name(spec.family_name), clean_name(spec.style_name)
    return ForgeReport(
        materials,
        n_cps,
        n_glyphs,
        warnings,
        out,
        issues=issues,
        family_name=family,
        style_name=style,
        full_name=f"{family} {style}",
        postscript_name=postscript_name(family, style),
        fs_type=fs_type,
        licence_notes=licence_notes,
    )


def forge(
    spec: ForgeSpec, output_path: str | Path, progress: ProgressFn | None = None, *, stamp: ForgeStamp | None = None
) -> ForgeReport:
    report_progress = progress or (lambda stage, fraction: None)
    errors = spec.validate()
    if errors:
        raise ForgeError("validate", None, " ".join(errors))
    shaping_errors = rule_errors(spec)
    if shaping_errors:
        index = shaping_errors[0][0]
        raise ForgeError(
            "validate",
            spec.materials[index].face.display_name,
            " ".join(message for _, _, message in shaping_errors),
            code="aat_unsupported_script",
            material_index=index,
        )
    stamp = stamp or new_stamp()
    report_progress("plan", 0.0)
    p = plan(spec)
    fs_type, _, licence_description = _licence_summary(spec, p)
    base = spec.materials[spec.base_index]
    out = Path(output_path)
    with tempfile.TemporaryDirectory(prefix="fontplayground-") as tmp:
        workdir = Path(tmp)
        prepared: list[PreparedFont] = []
        n = len(spec.materials)
        for i, m in enumerate(spec.materials):
            report_progress(f"prepare:{m.face.display_name}", 0.05 + 0.6 * i / n)
            try:
                prepared.append(
                    prepare(
                        m, p.assignments[i], base.face.upem, spec.resolved_weight(i), spec.resolved_scale(i), workdir, i
                    )
                )
            except ForgeError:
                raise
            except Exception as e:
                raise ForgeError("prepare", m.face.display_name, f"{type(e).__name__}: {e}") from e
        notices, notices_left_out = _carried_notices(p, prepared, M.notice_budget(spec, stamp, licence_description))
        report_progress("merge", 0.7)
        try:
            font = M.merge_fonts([pf.path for pf in prepared])
        except Exception as e:
            raise ForgeError("merge", None, f"{type(e).__name__}: {e}") from e
        glyphs = len(font.getGlyphOrder())
        if glyphs > M.MAX_GLYPHS:
            raise ForgeError(
                "merge",
                None,
                f"result has {glyphs} glyphs; TrueType allows {M.MAX_GLYPHS}. "
                "Assign fewer scripts or remove a material.",
                code="glyph_limit",
            )
        report_progress("finish", 0.85)
        base_font = TTFont(prepared[spec.base_index].path)
        try:
            weight = spec.resolved_weight(spec.base_index) or base.face.weight_class
            M.finish(
                font,
                spec,
                base_font,
                set(p.source),
                weight,
                stamp=stamp,
                fs_type=fs_type,
                licence_description=licence_description,
                notices=notices,
            )
            omitted, first = M.finalize_cmap(font)
            out.parent.mkdir(parents=True, exist_ok=True)
            font.save(str(out))
        except ForgeError:
            raise
        except Exception as e:
            raise ForgeError("finish", None, f"{type(e).__name__}: {e}") from e
        finally:
            base_font.close()
            font.close()
    report_progress("verify", 0.95)
    n_cps, n_glyphs = M.verify(out, set(p.source))
    forge_issues = []
    if omitted:
        note = (
            f"{omitted:,} characters from U+{first:04X} up are only in the font's full Unicode character map; "
            "current apps read it, but very old apps that read only the basic map will not show them"
        )
        forge_issues.append(Issue("cmap_format4_partial", "warning", None, None, note))
    added = sum(part.bold_added_bytes for part in prepared)
    final_size = out.stat().st_size
    if added > 0 and added > final_size - added:
        index = max(range(len(prepared)), key=lambda i: prepared[i].bold_added_bytes)

        def size(number: int) -> str:
            return f"{number / 1_000_000:.1f} MB" if number >= 1_000_000 else f"{max(1, round(number / 1000))} KB"

        note = (
            f"synthetic bold more than doubled the file size ({size(final_size - added)} without it, "
            f"{size(final_size)} with it); a heavier weight of this font, if you have one, gives a smaller, "
            "better-looking result"
        )
        forge_issues.append(
            Issue("bold_size_doubled", "warning", index, None, f"{spec.materials[index].face.display_name}: {note}")
        )
    report = _report(spec, p, prepared, n_cps, n_glyphs, str(out), forge_issues, notices_left_out)
    report_progress("done", 1.0)
    return report
