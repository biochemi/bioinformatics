#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"

PY="$ROOT_DIR/scripts"
CHECK_MODE=0


proceed_or_exit() {
  if ! ask_yes_no "Proceed to next step?"; then
    echo "Pipeline stopped by user."
    exit 0
  fi
}

download_pdb_if_missing() {
  local pdb_code="$1"
  local target="${pdb_code}.pdb"
  if [[ -f "$target" ]]; then
    echo "Found local PDB: $target"
    return
  fi
  ensure_wget
  echo "Downloading $pdb_code from RCSB..."
  wget -O "$target" "https://files.rcsb.org/download/${pdb_code}.pdb"
}

extract_receptor_ligand() {
  local pdb="$1"
  local ligand="$2"
  echo "Available non-protein HET residues (excluding HOH):"
  awk '$1=="HETATM" && $4!="HOH" {print $4}' "$pdb" | sort -u

  awk '$1=="ATOM" || ($1=="HETATM" && $4=="'"$ligand"'")' "$pdb" > complex_clean_tmp.pdb
  awk '$1=="ATOM"' complex_clean_tmp.pdb > receptor.pdb
  awk '$1=="HETATM" && $4=="'"$ligand"'"' complex_clean_tmp.pdb > ligand.pdb

  echo "Generated receptor.pdb and ligand.pdb"
  rm -f complex_clean_tmp.pdb
}

prepare_forcefield_and_receptor() {
  local ff_choice="$1"
  local ff_tgz
  local ff_url

  if [[ "$ff_choice" == "2026" ]]; then
    ff_tgz="charmm36-feb2026_cgenff-5.0.ff.tgz"
    ff_url="https://mackerell.umaryland.edu/download.php?filename=CHARMM_ff_params_files/charmm36-feb2026_cgenff-5.0.ff.tgz"
  else
    ff_tgz="charmm36-jul2022.ff.tgz"
    ff_url="https://mackerell.umaryland.edu/download.php?filename=CHARMM_ff_params_files/charmm36-jul2022.ff.tgz"
  fi

  if ! ls charmm36*.ff >/dev/null 2>&1; then
    if [[ ! -f "$ff_tgz" ]]; then
      ensure_wget
      wget -O "$ff_tgz" "$ff_url"
    fi
    tar -zxvf "$ff_tgz"
  fi

  echo "Running pdb2gmx with forcefield option 1 by default."
  if ask_yes_no "Use default forcefield option 1?"; then
    printf '1\n1\n' | gmx pdb2gmx -f receptor.pdb -o receptor.gro -water tip3p
  else
    gmx pdb2gmx -f receptor.pdb -o receptor.gro -water tip3p
  fi
  [[ -f receptor.gro ]] || { echo "receptor.gro not generated"; exit 1; }
  echo "Generated receptor.gro"
}

convert_ligand_to_mol2() {
  local method="$1"
  if [[ "$method" == "avogadro" ]]; then
    echo "Please create ligand.mol2 manually in Avogadro and copy to working directory."
    wait_for_file ligand.mol2
  else
    if ! command_exists obabel; then
      if ask_yes_no "Open Babel not found. Install with apt-get?"; then
        apt-get update && apt-get install -y openbabel
      elif ask_yes_no "Try pip install openbabel-wheel?"; then
        python3 -m pip install --user openbabel-wheel
      else
        echo "Cannot proceed without ligand.mol2"; exit 1
      fi
    fi
    run_or_fail obabel ligand.pdb -O ligand.mol2 -h
  fi

  python3 "$PY/fix_name_number.py" ligand.mol2 ligand.mol2 --resname ligand --resnum 1
}

sort_bonds() {
  if [[ ! -f sort_mol2_bonds.pl ]]; then
    ensure_wget
    wget -O sort_mol2_bonds.pl http://www.mdtutorials.com/gmx/complex/Files/sort_mol2_bonds.txt
  fi
  perl sort_mol2_bonds.pl ligand.mol2 ligand_fix.mol2
}

cgenff_manual_step() {
  cat <<MSG
Manual CGenFF server step:
  URL: https://app.cgenff.com/login
  Use your own CGenFF credentials to login.
Do:
  1) Upload ligand_fix.mol2
  2) Verify structure
  3) Run CGenFF and download ligand_f.zip + ligand_f_gromacs.zip
MSG

  while true; do
    if ask_yes_no "Finished server step and downloaded both ZIP files?"; then
      if [[ -f ligand_f.zip && -f ligand_f_gromacs.zip ]]; then
        unzip -o ligand_f.zip
        unzip -o ligand_f_gromacs.zip
        break
      fi
      echo "Missing ligand_f.zip and/or ligand_f_gromacs.zip in $(pwd)."
    fi
  done

  for f in ligand_f.mol2 ligand_f.cgenff.mol2 ligand_f.str ligand_f_gmx.pdb ligand_f_gmx.top; do
    [[ -f "$f" ]] && echo "Found: $f" || echo "Missing: $f"
  done
}

setup_ligand_itp() {
  cp ligand_f_gmx.top ligand_gmx.itp
  python3 "$PY/fix_itp.py" ligand_gmx.itp ligand_gmx.itp
}

build_complex_step() {
  if [[ ! -f cgenff_charmm2gmx_py3_nx2.py ]]; then
    wget -O cgenff_charmm2gmx_py3_nx2.py "https://mackerell.umaryland.edu/download.php?filename=CHARMM_ff_params_files/cgenff_charmm2gmx_py3_nx2.py"
  fi

  python3 - <<'PY'
import importlib, sys
for m in ("numpy", "networkx"):
    try:
        importlib.import_module(m)
    except Exception:
        print(m)
        sys.exit(1)
print("ok")
PY
  if [[ $? -ne 0 ]]; then
    echo "numpy/networkx missing. Install and retry."
    exit 1
  fi

  python3 cgenff_charmm2gmx_py3_nx2.py ligand ligand_f.mol2 ligand_f.str charmm36.ff
  gmx editconf -f ligand_ini.pdb -o ligand.gro

  [[ -f receptor.gro && -f ligand.gro ]] || { echo "Missing receptor.gro or ligand.gro"; exit 1; }
  python3 "$PY/build_complex.py" receptor.gro ligand.gro complex.gro
}

update_topol_for_complex() {
  python3 "$PY/fix_topol.py" topol.top
  tail -n 12 topol.top
}

choose_box_and_solvate() {
  local box
  box=$(choose_option "Choose box type" "cubic" "triclinic" "octahedron" "dodecahedron")
  gmx editconf -f complex.gro -o newbox.gro -bt "$box" -d 1.0
  gmx solvate -cp newbox.gro -cs spc216.gro -p topol.top -o solv.gro
  echo "Please visualize solv.gro in VMD if desired."
}

ensure_mdp() {
  local mdp="$1"
  local url="$2"
  if [[ ! -f "$mdp" ]]; then
    wget -O "$mdp" "$url"
  fi
}

maybe_modify_nsteps() {
  local mdp="$1"
  local default_nsteps="$2"
  echo "Current default nsteps suggestion: $default_nsteps"
  local opt
  opt=$(choose_option "nsteps option" "keep" "change")
  if [[ "$opt" == "change" ]]; then
    read -r -p "Enter new nsteps: " n
    python3 "$PY/modify_mdp.py" "$mdp" --nsteps "$n"
  fi
}

check_environment() {
  step_banner "CHECK" "Environment and script validation"
  local missing=0
  for cmd in bash python3 wget perl unzip; do
    if command_exists "$cmd"; then
      echo "[OK] $cmd found"
    else
      echo "[MISSING] $cmd not found"
      missing=1
    fi
  done

  if command_exists gmx; then
    echo "[OK] gmx found"
    gmx --version | head -n 5
  else
    echo "[MISSING] gmx not found in PATH"
    missing=1
  fi

  bash -n "$ROOT_DIR/gmx_fayyaz_pipeline.sh" "$ROOT_DIR/lib/common.sh"
  python3 -m py_compile "$PY"/*.py

  if [[ $missing -eq 1 ]]; then
    echo "Environment check finished with missing dependencies."
    return 1
  fi
  echo "Environment check passed."
  return 0
}

run_ions_em_eq_prod() {
  step_banner "Ions" "Adding ions"
  ensure_mdp ions.mdp http://www.mdtutorials.com/gmx/complex/Files/ions.mdp
  maybe_modify_nsteps ions.mdp 50000
  gmx grompp -f ions.mdp -c solv.gro -p topol.top -o ions.tpr
  printf 'SOL\n' | gmx genion -s ions.tpr -o solv_ions.gro -p topol.top -pname NA -nname CL -neutral
  tail -n 15 topol.top

  step_banner "EM" "Energy minimization"
  ensure_mdp em.mdp http://www.mdtutorials.com/gmx/complex/Files/em.mdp
  maybe_modify_nsteps em.mdp 50000
  gmx grompp -f em.mdp -c solv_ions.gro -p topol.top -o em.tpr || true
  gmx mdrun -v -deffnm em || true
  tail -n 20 em.log || true

  step_banner "Equilibration" "Ligand restraints + NVT/NPT"
  printf '0 & ! a H*\nq\n' | gmx make_ndx -f ligand.gro -o index_ligand.ndx
  gmx genrestr -f ligand.gro -n index_ligand.ndx -o posre_ligand.itp -fc 1000 1000 1000

  ensure_mdp nvt.mdp http://www.mdtutorials.com/gmx/complex/Files/nvt.mdp
  maybe_modify_nsteps nvt.mdp 50000
  tc=$(choose_option "Choose tc-grps" "System" "Protein_LIG Water_and_ions")
  if [[ "$tc" == "System" ]]; then
    python3 "$PY/modify_mdp.py" nvt.mdp --tc-grps "System"
  else
    python3 "$PY/modify_mdp.py" nvt.mdp --tc-grps "Protein_ligand Water_and_ions"
  fi
  gmx grompp -f nvt.mdp -c em.gro -r em.gro -p topol.top -o nvt.tpr || true
  gmx mdrun -deffnm nvt || true

  ensure_mdp npt.mdp http://www.mdtutorials.com/gmx/complex/Files/npt.mdp
  maybe_modify_nsteps npt.mdp 50000
  gmx grompp -f npt.mdp -c nvt.gro -t nvt.cpt -r nvt.gro -p topol.top -o npt.tpr || true
  gmx mdrun -deffnm npt || true

  ensure_mdp md.mdp http://www.mdtutorials.com/gmx/complex/Files/md.mdp
  maybe_modify_nsteps md.mdp 50000
  gmx grompp -f md.mdp -c npt.gro -t npt.cpt -p topol.top -o md_0_10.tpr || true
  gmx mdrun -deffnm md_0_10 || true
}

parse_args() {
  if [[ ${1:-} == "--check" ]]; then
    CHECK_MODE=1
  fi
}

main() {
  parse_args "$@"
  if [[ $CHECK_MODE -eq 1 ]]; then
    check_environment
    return $?
  fi

  step_banner "0" "Check GROMACS"
  if ! command_exists gmx; then
    echo "GROMACS (gmx) not found in PATH."
    exit 1
  fi
  gmx --version | head -n 5
  proceed_or_exit

  step_banner "Welcome" "welcome to the GMX_fayyaz pipeline"
  proceed_or_exit

  step_banner "1" "Fetch input PDB"
  read -r -p "Enter project name (optional): " project_name
  read -r -p "Enter PDB code (e.g., 3HBT): " pdb_code
  pdb_code="${pdb_code^^}"
  download_pdb_if_missing "$pdb_code"
  proceed_or_exit

  step_banner "2" "Protein and Ligand Preparation"
  read -r -p "Enter ligand residue name to keep (3-letter code): " ligand_name
  extract_receptor_ligand "${pdb_code}.pdb" "$ligand_name"
  proceed_or_exit

  step_banner "3" "Force field + receptor GRO"
  ff=$(choose_option "Choose CHARMM FF package" "2026" "2022")
  prepare_forcefield_and_receptor "$ff"
  proceed_or_exit

  step_banner "4" "Ligand MOL2 generation"
  m=$(choose_option "Choose method" "avogadro" "openbabel")
  convert_ligand_to_mol2 "$m"
  proceed_or_exit

  step_banner "5" "Sort MOL2 bonds"
  sort_bonds
  proceed_or_exit

  step_banner "6" "Manual CGenFF"
  cgenff_manual_step
  proceed_or_exit

  step_banner "7" "Fix ligand ITP"
  setup_ligand_itp
  proceed_or_exit

  step_banner "8" "Build complex"
  build_complex_step
  proceed_or_exit

  step_banner "9" "Build topology"
  update_topol_for_complex
  proceed_or_exit

  step_banner "10" "Define box and solvate"
  choose_box_and_solvate
  proceed_or_exit

  step_banner "11-14" "Ions, EM, NVT, NPT, MD"
  run_ions_em_eq_prod

  echo "Pipeline completed (check outputs and logs for each stage)."
}

main "$@"
