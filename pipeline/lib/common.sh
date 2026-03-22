#!/usr/bin/env bash
set -euo pipefail

step_banner() {
  local step="$1"
  local title="$2"
  printf '\n============================================================\n'
  printf 'Step %s: %s\n' "$step" "$title"
  printf '============================================================\n'
}

ask_yes_no() {
  local prompt="${1:-Proceed?}"
  local answer
  while true; do
    read -r -p "$prompt [y/n]: " answer || true
    case "${answer,,}" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

wait_for_file() {
  local file="$1"
  while [[ ! -f "$file" ]]; do
    echo "File not found: $file"
    read -r -p "Copy it into $(pwd) then press Enter to re-check..."
  done
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

choose_option() {
  local prompt="$1"
  shift
  local options=("$@")
  local i
  echo "$prompt"
  for i in "${!options[@]}"; do
    printf '  %d) %s\n' "$((i+1))" "${options[$i]}"
  done
  while true; do
    read -r -p "Select option number: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#options[@]} )); then
      echo "${options[$((choice-1))]}"
      return 0
    fi
    echo "Invalid choice."
  done
}

ensure_wget() {
  if ! command_exists wget; then
    echo "wget is required but not found. Please install wget first."
    exit 1
  fi
}

run_or_fail() {
  echo "+ $*"
  "$@"
}
