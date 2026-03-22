#!/usr/bin/env python3
"""Insert ligand include and ensure ligand entry in [ molecules ] of topol.top."""
from __future__ import annotations
import argparse
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("topol")
    ap.add_argument("--protein-name", default="Protein_chain_A")
    ap.add_argument("--ligand-name", default="ligand")
    args = ap.parse_args()

    lines = Path(args.topol).read_text(encoding="utf-8", errors="ignore").splitlines()

    include_line = '#include "ligand_gmx.itp"'
    include_comment = '; Include ligand parameters'

    if include_line not in lines:
        insert_idx = None
        for i, line in enumerate(lines):
            if 'forcefield.itp' in line:
                insert_idx = i + 1
                break
        if insert_idx is None:
            insert_idx = 0
        lines[insert_idx:insert_idx] = [include_comment, include_line]

    mol_idx = None
    for i, line in enumerate(lines):
        if line.strip().lower() == '[ molecules ]':
            mol_idx = i
            break

    if mol_idx is None:
        lines.extend(['', '[ molecules ]', '; Compound        #mols', f'{args.protein_name}     1', f'{args.ligand_name}     1'])
    else:
        tail = lines[mol_idx + 1:]
        has_ligand = any(l.strip().startswith(args.ligand_name) for l in tail)
        if not has_ligand:
            insert = mol_idx + 1
            while insert < len(lines) and (lines[insert].strip().startswith(';') or not lines[insert].strip()):
                insert += 1
            # Keep protein first, then ligand
            lines.insert(insert + 1, f'{args.ligand_name}                 1')

    Path(args.topol).write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f'Updated {args.topol} for complex topology.')


if __name__ == '__main__':
    main()
