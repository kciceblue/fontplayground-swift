"""Data model for a forge run: inputs, plan, reports and errors."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal

from fpengine.face import FontFace
from fpengine.naming import clean_name


class ForgeError(Exception):
    def __init__(
        self,
        stage: str,
        material: str | None,
        message: str,
        *,
        code: str | None = None,
        material_index: int | None = None,
    ):
        self.stage, self.material, self.message = stage, material, message
        self.code, self.material_index = code, material_index
        where = f"{stage} ({material})" if material else stage
        super().__init__(f"[{where}] {message}")


@dataclass
class MaterialSpec:
    face: FontFace
    weight: int | None = None  # None -> ForgeSpec.default_weight
    scale: float | None = None  # None -> ForgeSpec.default_scale


@dataclass
class ForgeSpec:
    materials: list[MaterialSpec] = field(default_factory=list)  # priority order
    base_index: int = 0
    script_rules: dict[str, int | None] = field(default_factory=dict)  # group id -> material index
    default_weight: int | None = None  # None -> "as is"
    default_scale: float = 1.0
    family_name: str = "Forged"
    style_name: str = "Regular"

    def resolved_weight(self, i: int) -> int | None:
        w = self.materials[i].weight
        return w if w is not None else self.default_weight

    def resolved_scale(self, i: int) -> float:
        s = self.materials[i].scale
        return s if s is not None else self.default_scale

    def validate(self) -> list[str]:
        errors: list[str] = []
        n = len(self.materials)
        if n == 0:
            return ["Add at least one material."]
        if not 0 <= self.base_index < n:
            errors.append("Base material is out of range.")
        for m in self.materials:
            if not m.face.supported:
                errors.append(f"{m.face.display_name}: {m.face.unsupported_reason}")
        if not self.family_name.strip():
            errors.append("Family name is empty.")
        if not self.style_name.strip():
            errors.append("Style name is empty.")
        family, style = clean_name(self.family_name), clean_name(self.style_name)
        if family.startswith("."):
            errors.append("Family name can't start with “.”: macOS hides fonts whose names start with a dot.")
        if any(ord(character) < 0x20 or ord(character) == 0x7F for character in family):
            errors.append("Family name contains a control character.")
        if any(ord(character) < 0x20 or ord(character) == 0x7F for character in style):
            errors.append("Style name contains a control character.")
        for g, idx in self.script_rules.items():
            if idx is not None and not 0 <= idx < n:
                errors.append(f"Rule for {g} points to a missing material.")
        base_upem = self.materials[self.base_index].face.upem if 0 <= self.base_index < n else None
        for i, m in enumerate(self.materials):
            s = self.resolved_scale(i)
            if not 0.1 <= s <= 10:
                errors.append(f"{m.face.display_name}: scale {s:g} must be between 0.1 and 10.")
            elif base_upem and round(base_upem * s) > 16384:
                errors.append(
                    f"{m.face.display_name}: scale {s * 100:g}% is too large for a {base_upem}-unit base "
                    f"(maximum {16384 / base_upem * 100:.0f}%)."
                )
            w = self.resolved_weight(i)
            if w is not None and not 1 <= w <= 1000:
                errors.append(f"{m.face.display_name}: weight {w} must be between 1 and 1000.")
        return errors

    def to_dict(self) -> dict:
        return {
            "materials": [
                {"path": m.face.path, "index": m.face.index, "weight": m.weight, "scale": m.scale}
                for m in self.materials
            ],
            "base_index": self.base_index,
            "script_rules": dict(self.script_rules),
            "default_weight": self.default_weight,
            "default_scale": self.default_scale,
            "family_name": self.family_name,
            "style_name": self.style_name,
        }

    @classmethod
    def from_dict(cls, d: dict, faces_by_key: dict[tuple[str, int], FontFace]) -> ForgeSpec:
        materials, remap = [], {}
        for old, m in enumerate(d.get("materials", [])):
            face = faces_by_key.get((m["path"], m["index"]))
            if face is None:
                continue
            remap[old] = len(materials)
            materials.append(MaterialSpec(face, m.get("weight"), m.get("scale")))
        rules = {g: (remap.get(idx) if idx is not None else None) for g, idx in d.get("script_rules", {}).items()}
        return cls(
            materials=materials,
            base_index=remap.get(d.get("base_index", 0), 0),
            script_rules=rules,
            default_weight=d.get("default_weight"),
            default_scale=d.get("default_scale", 1.0),
            family_name=d.get("family_name", "Forged"),
            style_name=d.get("style_name", "Regular"),
        )


@dataclass
class Plan:
    assignments: dict[int, set[int]]  # material index -> code points (disjoint)
    source: dict[int, int]  # code point -> material index


@dataclass
class MaterialReport:
    name: str
    codepoints: int
    groups: list[str]
    warnings: list[str] = field(default_factory=list)


IssueSeverity = Literal["warning", "error"]


@dataclass(frozen=True)
class Issue:
    """One machine-readable report item (contracts.md §4 `issues`, engine-metadata.md §S5).

    `message` is the full sentence. For a per-material issue it is f"{display_name}: {note}", exactly the line
    that also appears in ForgeReport.warnings; for a report-level issue (material_index None) it is the note itself.
    """

    code: str
    severity: IssueSeverity
    material_index: int | None
    group: str | None
    message: str

    def to_dict(self) -> dict[str, object]:
        """Keys in schema order; equal to dataclasses.asdict(self)."""
        return {
            "code": self.code,
            "severity": self.severity,
            "material_index": self.material_index,
            "group": self.group,
            "message": self.message,
        }


@dataclass(frozen=True)
class LicenceNote:
    licence_class: str
    material_indexes: tuple[int, ...]
    text: str


@dataclass
class ForgeReport:
    materials: list[MaterialReport]
    total_codepoints: int
    total_glyphs: int
    warnings: list[str]
    output_path: str
    issues: list[Issue] = field(default_factory=list)
    family_name: str = ""
    style_name: str = ""
    postscript_name: str = ""
    full_name: str = ""
    fs_type: int = 0
    licence_notes: list[LicenceNote] = field(default_factory=list)

    def as_text(self) -> str:
        from fpengine.scripts import LABELS

        lines = [
            f"Output: {self.output_path}",
            f"Characters: {self.total_codepoints}   Glyphs: {self.total_glyphs}",
            "",
        ]
        for m in self.materials:
            groups = ", ".join(LABELS.get(g, g) for g in m.groups) or "-"
            lines.append(f"{m.name}: {m.codepoints} characters  [{groups}]")
            lines += [f"    warning: {w}" for w in m.warnings]
        if self.warnings:
            lines += ["", "Warnings:"] + [f"  - {w}" for w in self.warnings]
        if self.licence_notes:
            lines += ["", "Licence:"]
            for note in self.licence_notes:
                names = ", ".join(self.materials[i].name for i in note.material_indexes)
                lines.append(f"  - {note.text} ({names})")
        return "\n".join(lines)
