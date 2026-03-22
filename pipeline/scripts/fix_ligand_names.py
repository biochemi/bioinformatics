#!/usr/bin/env python3
"""Simple helper to normalize ligand atom names between .gro and .itp contexts."""
from __future__ import annotations
import argparse
from pathlib import Path
import re


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('gro_file')
    ap.add_argument('--resname', default='LIG')
    args = ap.parse_args()

    path = Path(args.gro_file)
    lines = path.read_text(encoding='utf-8', errors='ignore').splitlines()
    natoms = int(lines[1].strip())

    out = lines[:2]
    atom_lines = lines[2:2 + natoms]
    for line in atom_lines:
        if len(line) >= 10:
            # GRO fixed-width: resname at columns 6-10
            patched = f"{line[:5]}{args.resname:>5}{line[10:]}"
            patched = re.sub(r'\bH\d+\b', lambda m: f"H{int(m.group(0)[1:]):02d}", patched)
            out.append(patched)
        else:
            out.append(line)
    out.extend(lines[2 + natoms:])

    path.write_text('\n'.join(out) + '\n', encoding='utf-8')
    print(f'Normalized residue name in {args.gro_file} to {args.resname}')


if __name__ == '__main__':
    main()
