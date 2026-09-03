#!/usr/bin/env bash
#
# Shared helpers for the bare+worktree scripts (sw, gbare).
# Source it: source "${BASH_SOURCE[0]%/*}/../lib/worktree.sh"
#
# Convention: scripts print only a directory on stdout (the .zshrc wrapper
# turns it into cd); every message goes to stderr.

_msg() { #{{{
  echo "$*" >&2
}
#}}}: _msg

_die() { #{{{
  _msg "$*"
  exit 1
}
#}}}: _die

_ask() { #{{{
  # Yes/no question; returns 1 for anything but y/Y.
  local yn
  read -n 1 -r -p ">> $1 [y/N]: " yn
  echo >&2
  [[ $yn == [yY] ]]
}
#}}}: _ask

_prompt() { #{{{
  # Yes/no question; anything but y/Y aborts the script.
  _ask "$1" || _die "Aborted."
}
#}}}: _prompt

_flatten() { #{{{
  # feat/topic -> feat-topic, so worktrees are never nested
  echo "${1//\//-}"
}
#}}}: _flatten

_worktreePath() { #{{{
  # $1 = branch name; empty selects the bare repo. Prints nothing when absent.
  local want="$1" path="" line
  while IFS= read -r line; do
    case $line in
    "worktree "*) path="${line#worktree }" ;;
    'bare') [[ -z $want ]] && { echo "$path"; return 0; } ;;
    "branch refs/heads/$want") [[ -n $want ]] && { echo "$path"; return 0; } ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null)
  return 0
}
#}}}: _worktreePath

_relpath() { #{{{
  # Relative path from directory $1 to path $2 (both absolute, no symlink resolution).
  local from="${1%/}" to="$2" up="" common
  common="$from"
  while [[ -n $common && $to != "$common"/* ]]; do
    common="${common%/*}"
    up+="../"
  done
  echo "${up}${to#"$common"/}"
}
#}}}: _relpath
