# shellcheck shell=bash
# Bordered-block logger shared across crons. Source from an entrypoint:
#
#   . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_lib/log.sh"
#
# All block functions take the log file path as $1 — no hidden globals.

readonly _C_GREEN='\033[0;32m'
readonly _C_YELLOW='\033[0;33m'
readonly _C_RED='\033[0;31m'
readonly _C_DIM='\033[2m'
readonly _C_RESET='\033[0m'

_color() {
  local name="$1" text="$2"
  case "$name" in
  green)  printf '%b%s%b' "$_C_GREEN"  "$text" "$_C_RESET" ;;
  yellow) printf '%b%s%b' "$_C_YELLOW" "$text" "$_C_RESET" ;;
  red)    printf '%b%s%b' "$_C_RED"    "$text" "$_C_RESET" ;;
  dim)    printf '%b%s%b' "$_C_DIM"    "$text" "$_C_RESET" ;;
  *)      printf '%s' "$text" ;;
  esac
}

_block_open() {
  local log_file="$1" ts
  ts=$(date +"%d-%h-%y | %I:%M %p")
  printf '┌─ %s ──────────────────────────────\n' "$ts" >>"$log_file"
}

_block_line() {
  local log_file="$1" text="$2"
  printf '│  %b\n' "$text" >>"$log_file"
}

_block_close() {
  local log_file="$1"
  printf '└─────────────────────────────────────────────────────\n\n' >>"$log_file"
}
