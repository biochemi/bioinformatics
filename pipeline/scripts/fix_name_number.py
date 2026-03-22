#!/usr/bin/env python3
"""Normalize residue name/number in a MOL2 file.
Usage: fix_name_number.py input.mol2 output.mol2 --resname ligand --resnum 1
"""
from __future__ import annotations
import argparse


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("input")
    p.add_argument("output")
    p.add_argument("--resname", default="ligand")
    p.add_argument("--resnum", type=int, default=1)
    args = p.parse_args()

    with open(args.input, "r", encoding="utf-8", errors="ignore") as f:
      lines = f.readlines()

    in_atom = False
    out = []
    for line in lines:
        if line.startswith("@<TRIPOS>ATOM"):
            in_atom = True
            out.append(line)
            continue
        if line.startswith("@<TRIPOS>") and not line.startswith("@<TRIPOS>ATOM"):
            in_atom = False
            out.append(line)
            continue

        if in_atom and line.strip():
            parts = line.split()
            if len(parts) >= 8:
                parts[7] = str(args.resnum)
            if len(parts) >= 9:
                parts[8] = args.resname
            if len(parts) >= 2 and parts[1] == "*****":
                parts[1] = "ligand"
            line = " ".join(parts) + "\n"
        out.append(line)

    with open(args.output, "w", encoding="utf-8") as f:
        f.writelines(out)

    print(f"Wrote normalized MOL2: {args.output}")


if __name__ == "__main__":
    main()
