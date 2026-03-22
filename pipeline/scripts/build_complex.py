#!/usr/bin/env python3
"""Build complex.gro by appending ligand coordinates to receptor coordinates."""
from __future__ import annotations
import argparse
from pathlib import Path


def parse_gro(path: Path):
    lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    title = lines[0]
    natoms = int(lines[1].strip())
    atoms = lines[2:2 + natoms]
    box = lines[2 + natoms]
    return title, natoms, atoms, box


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("receptor_gro")
    ap.add_argument("ligand_gro")
    ap.add_argument("output_gro")
    args = ap.parse_args()

    rt, rn, ra, rbox = parse_gro(Path(args.receptor_gro))
    lt, ln, la, _ = parse_gro(Path(args.ligand_gro))

    total = rn + ln
    out = [f"{rt} + {lt}", str(total), *ra, *la, rbox]
    Path(args.output_gro).write_text("\n".join(out) + "\n", encoding="utf-8")

    print(f"Receptor atoms: {rn}")
    print(f"Ligand atoms:   {ln}")
    print(f"Complex atoms:  {total}")
    print(f"Wrote {args.output_gro}")


if __name__ == "__main__":
    main()
