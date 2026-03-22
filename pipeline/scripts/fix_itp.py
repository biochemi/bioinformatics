#!/usr/bin/env python3
"""Patch ligand_gmx.itp for inclusion in a protein-ligand system."""
from __future__ import annotations
import argparse
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("input_itp")
    ap.add_argument("output_itp")
    ap.add_argument("--ffbonded", default="charmm36.ff/jz4_ffbonded.itp")
    args = ap.parse_args()

    src = Path(args.input_itp).read_text(encoding="utf-8", errors="ignore").splitlines()
    ffbonded_path = Path(args.ffbonded)
    ffbonded_txt = ffbonded_path.read_text(encoding="utf-8", errors="ignore") if ffbonded_path.exists() else None

    out: list[str] = []
    changed = []
    skip_tail = False
    in_moleculetype = False
    moleculetype_renamed = False

    for i, line in enumerate(src):
        if skip_tail:
            continue

        s = line.strip()
        if '#include "charmm36.ff/forcefield.itp"' in s:
            changed.append("Removed forcefield include line")
            continue

        if 'Include water topology' in line:
            changed.append("Removed water/ions/system tail from '; Include water topology' onward")
            skip_tail = True
            continue

        if '#include "charmm36.ff/jz4_ffbonded.itp"' in s:
            if ffbonded_txt:
                out.append("; BEGIN inlined charmm36.ff/jz4_ffbonded.itp")
                out.extend(ffbonded_txt.splitlines())
                out.append("; END inlined charmm36.ff/jz4_ffbonded.itp")
                changed.append("Inlined jz4_ffbonded.itp")
            else:
                out.append("; WARNING: missing charmm36.ff/jz4_ffbonded.itp, keeping include")
                out.append(line)
            continue

        if '#include "posre.itp"' in s:
            out.append(line.replace('"posre.itp"', '"posre_ligand.itp"'))
            changed.append("Updated posre include to posre_ligand.itp")
            continue

        if s.startswith("[ moleculetype ]"):
            in_moleculetype = True
            out.append(line)
            continue

        if in_moleculetype and s and not s.startswith(";"):
            cols = line.split()
            if cols and cols[0].lower() == "other":
                cols[0] = "ligand"
                out.append((" ".join(cols)))
                moleculetype_renamed = True
                changed.append("Renamed moleculetype from Other to ligand")
            else:
                out.append(line)
            in_moleculetype = False
            continue

        out.append(line)

    Path(args.output_itp).write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"Wrote modified ITP: {args.output_itp}")
    if not moleculetype_renamed:
        print("WARNING: did not find 'Other' moleculetype entry to rename.")
    print("Changes made:")
    for c in changed:
        print(f"- {c}")


if __name__ == "__main__":
    main()
