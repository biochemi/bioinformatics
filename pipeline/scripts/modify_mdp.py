#!/usr/bin/env python3
"""Modify key=value entries in MDP files (e.g., nsteps, tc-grps, define)."""
from __future__ import annotations
import argparse
from pathlib import Path


def set_key(lines: list[str], key: str, value: str) -> list[str]:
    out = []
    found = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith(';') or '=' not in line:
            out.append(line)
            continue
        k = stripped.split('=', 1)[0].strip()
        if k == key:
            out.append(f"{key:<16} = {value}")
            found = True
        else:
            out.append(line)
    if not found:
        out.append(f"{key:<16} = {value}")
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("mdp")
    ap.add_argument("--nsteps", type=int)
    ap.add_argument("--tc-grps")
    ap.add_argument("--define")
    args = ap.parse_args()

    path = Path(args.mdp)
    lines = path.read_text(encoding='utf-8', errors='ignore').splitlines()

    if args.nsteps is not None:
        lines = set_key(lines, 'nsteps', str(args.nsteps))
    if args.tc_grps is not None:
        lines = set_key(lines, 'tc-grps', args.tc_grps)
    if args.define is not None:
        lines = set_key(lines, 'define', args.define)

    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f'Modified {args.mdp}')


if __name__ == '__main__':
    main()
