#!/usr/bin/env bash
#
# sgc - drive the sgcode/ two-repo workspace (landfast-backend + sgcode-agent)
# as one: switch, inspect, commit and push both worktrees in a single command.

set -euo pipefail

readonly SG_REPOS="${SG_REPOS:-$HOME/.repos/stackguardian}"
readonly ROOT="${SGCODE_ROOT:-$SG_REPOS/sgcode}"
readonly SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# name -> repo home (bare+worktree layout) and the sparse subdir it is pinned to
readonly NAMES=(backend agent)
declare -rA REPO=([backend]=landfast-infra2code-prototype [agent]=workflow-step-templates)
declare -rA SUBDIR=([backend]=landfast-backend [agent]=sgcode-agent)
# long-lived branches are never owned here: checked out detached at origin
readonly SHARED_BRANCHES=(main develop)

declare -a selected=("${NAMES[@]}")

usage() { #{{{
  cat <<EOF
Usage: sgc [--only backend|agent] <command> [args]

Workspace: $ROOT
  backend/  ${REPO[backend]}  (sparse: ${SUBDIR[backend]}/)
  agent/    ${REPO[agent]}  (sparse: ${SUBDIR[agent]}/)

Commands:
  init                         create missing worktrees (idempotent)
  status                       branch, ahead/behind and changes per repo
  fetch | pull                 fetch --prune | pull --ff-only
  switch <branch> [-c] [--from <base>] [--no-fetch]
                               switch both repos; -c creates the branch where
                               missing (base: origin/HEAD); main/develop are
                               checked out detached at origin
  commit [-feat|-fix|-docs] [-a] <msg>
                               commit via com.sh in each repo with staged
                               changes (-a stages everything first)
  push                         push -u origin HEAD where ahead / no upstream
  diff [args] | log [args]     per-repo pass-through
  each <git args...>           run a git command in every selected repo
  backend|agent <git args...>  run a git command in one repo

--only may appear anywhere and limits a command to one repo.
EOF
}
#}}}: usage

die() { printf 'sgc: %s\n' "$*" >&2; exit 1; }
warn() { printf 'sgc: %s\n' "$*" >&2; }
g() { local name="$1"; shift; git -C "$ROOT/$name" "$@"; }

is_shared() { #{{{
  local b
  for b in "${SHARED_BRANCHES[@]}"; do [[ "$1" == "$b" ]] && return 0; done
  return 1
}
#}}}: is_shared

describe_head() { #{{{
  local name="$1" branch ref
  branch="$(g "$name" branch --show-current)"
  if [[ -n "$branch" ]]; then
    printf '%s' "$branch"
    return
  fi
  ref="$(g "$name" for-each-ref --points-at HEAD --format='%(refname:short)' refs/remotes/origin \
    | grep -vxE 'origin(/HEAD)?' | head -1 || true)"
  printf 'detached@%s' "${ref:-$(g "$name" rev-parse --short HEAD)}"
}
#}}}: describe_head

tracking() { #{{{
  local name="$1" counts
  if ! g "$name" rev-parse --abbrev-ref '@{u}' &>/dev/null; then
    [[ -n "$(g "$name" branch --show-current)" ]] && printf ' (no upstream)'
    return 0
  fi
  counts="$(g "$name" rev-list --left-right --count 'HEAD...@{u}')"
  printf ' ↑%s ↓%s' "${counts%%$'\t'*}" "${counts##*$'\t'}"
}
#}}}: tracking

header() { printf '── %s [%s]%s\n' "$1" "$(describe_head "$1")" "$(tracking "$1")"; }

require_workspace() { #{{{
  local name
  for name in "${selected[@]}"; do
    [[ -e "$ROOT/$name/.git" ]] || die "$ROOT/$name missing — run 'sgc init'"
  done
}
#}}}: require_workspace

# Path of the worktree (other than ours) holding refs/heads/<branch>, if any.
held_by() { #{{{
  local name="$1" branch="$2" own path="" line
  own="$(cd "$ROOT/$name" && pwd -P)"
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      "branch refs/heads/$branch")
        if [[ "$(cd "$path" 2>/dev/null && pwd -P)" != "$own" ]]; then
          printf '%s' "$path"
          return
        fi
        ;;
    esac
  done < <(g "$name" worktree list --porcelain)
}
#}}}: held_by

has_ref() { g "$1" show-ref --verify --quiet "$2"; }

cmd_init() { #{{{
  local name home
  mkdir -p "$ROOT"
  for name in "${selected[@]}"; do
    if [[ -e "$ROOT/$name/.git" ]]; then
      echo "── $name: exists, skipping"
      continue
    fi
    home="$SG_REPOS/${REPO[$name]}/.bare"
    [[ -d "$home" ]] || die "$home not found"
    echo "── $name: adding worktree of ${REPO[$name]} (sparse: ${SUBDIR[$name]}/)"
    git -C "$home" fetch --prune --quiet origin
    git -C "$home" worktree add --detach --no-checkout "$ROOT/$name" origin/main
    g "$name" sparse-checkout set --cone "${SUBDIR[$name]}"
    g "$name" read-tree -mu HEAD
  done
}
#}}}: cmd_init

cmd_status() { #{{{
  local name
  for name in "${selected[@]}"; do
    header "$name"
    g "$name" status -s
  done
}
#}}}: cmd_status

cmd_fetch() { #{{{
  local name
  for name in "${selected[@]}"; do
    header "$name"
    g "$name" fetch --prune
  done
}
#}}}: cmd_fetch

cmd_pull() { #{{{
  local name
  for name in "${selected[@]}"; do
    header "$name"
    if [[ -z "$(g "$name" branch --show-current)" ]]; then
      echo "detached — skipping (use 'sgc switch <branch>')"
      continue
    fi
    g "$name" pull --ff-only
  done
}
#}}}: cmd_pull

cmd_switch() { #{{{
  local branch="" create=0 base="" fetch=1 name holder resolved
  while (( $# )); do
    case "$1" in
      -c) create=1 ;;
      --from) base="${2:?--from needs a base}"; shift ;;
      --no-fetch) fetch=0 ;;
      -*) die "switch: unknown option $1" ;;
      *) [[ -z "$branch" ]] || die "switch: one branch only"; branch="$1" ;;
    esac
    shift
  done
  [[ -n "$branch" ]] || die "switch: branch name required"

  # preflight every repo before touching any, so both move or neither does
  for name in "${selected[@]}"; do
    (( fetch )) && g "$name" fetch --prune --quiet origin
    if ! g "$name" diff --quiet || ! g "$name" diff --cached --quiet; then
      die "$name has uncommitted changes — commit or stash first (nothing switched)"
    fi
    if ! is_shared "$branch"; then
      holder="$(held_by "$name" "$branch")"
      [[ -z "$holder" ]] || die "$branch is checked out in $holder — free it there first (nothing switched)"
    fi
  done

  for name in "${selected[@]}"; do
    if is_shared "$branch"; then
      if has_ref "$name" "refs/remotes/origin/$branch"; then
        g "$name" switch --quiet --detach "origin/$branch"
      else
        warn "$name: no origin/$branch — left as is"
      fi
    elif [[ "$(g "$name" branch --show-current)" == "$branch" ]]; then
      :
    elif has_ref "$name" "refs/heads/$branch"; then
      g "$name" switch --quiet "$branch"
    elif has_ref "$name" "refs/remotes/origin/$branch"; then
      g "$name" switch --quiet --track "origin/$branch"
    elif (( create )); then
      resolved="${base:-$(g "$name" rev-parse --abbrev-ref origin/HEAD 2>/dev/null || echo origin/main)}"
      has_ref "$name" "refs/remotes/origin/$resolved" && resolved="origin/$resolved"
      g "$name" switch --quiet --no-track -c "$branch" "$resolved"
    else
      warn "$name: no branch $branch (use -c to create) — left as is"
    fi
    header "$name"
  done
}
#}}}: cmd_switch

cmd_commit() { #{{{
  local type="" all=0 name
  local -a words=()
  while (( $# )); do
    case "$1" in
      -feat|-fix|-docs) type="$1" ;;
      -a) all=1 ;;
      *) words+=("$1") ;;
    esac
    shift
  done
  (( ${#words[@]} )) || die "commit: message required"

  for name in "${selected[@]}"; do
    header "$name"
    (( all )) && g "$name" add -A
    if g "$name" diff --cached --quiet; then
      echo "nothing staged — skipping"
      continue
    fi
    (cd "$ROOT/$name" && "$SCRIPTS_DIR/com.sh" ${type:+"$type"} "${words[@]}")
  done
}
#}}}: cmd_commit

cmd_push() { #{{{
  local name branch
  for name in "${selected[@]}"; do
    header "$name"
    branch="$(g "$name" branch --show-current)"
    if [[ -z "$branch" ]]; then
      echo "detached — refusing to push"
      continue
    fi
    if is_shared "$branch"; then
      echo "on $branch — refusing to push"
      continue
    fi
    if g "$name" rev-parse --abbrev-ref '@{u}' &>/dev/null \
      && [[ "$(g "$name" rev-list --count '@{u}..HEAD')" == 0 ]]; then
      echo "up to date — skipping"
      continue
    fi
    g "$name" push -u origin HEAD
  done
}
#}}}: cmd_push

cmd_each() { #{{{
  local name
  for name in "${selected[@]}"; do
    header "$name"
    g "$name" --no-pager "$@"
  done
}
#}}}: cmd_each

main() { #{{{
  local -a args=()
  while (( $# )); do
    case "$1" in
      --only)
        [[ -n "${2:-}" && -n "${REPO[$2]:-}" ]] || die "--only takes: ${NAMES[*]}"
        selected=("$2")
        shift
        ;;
      *) args+=("$1") ;;
    esac
    shift
  done
  set -- "${args[@]}"

  local cmd="${1:-status}"
  (( $# )) && shift

  case "$cmd" in
    -h|--help|help) usage; return ;;
    init) cmd_init; return ;;
  esac

  require_workspace
  case "$cmd" in
    status|st) cmd_status ;;
    fetch) cmd_fetch ;;
    pull) cmd_pull ;;
    switch|sw) cmd_switch "$@" ;;
    commit|ci) cmd_commit "$@" ;;
    push) cmd_push ;;
    diff) cmd_each diff "$@" ;;
    log) (( $# )) || set -- --oneline -10; cmd_each log "$@" ;;
    each) (( $# )) || die "each: git args required"; cmd_each "$@" ;;
    backend|agent) selected=("$cmd"); cmd_each "$@" ;;
    *) usage >&2; exit 1 ;;
  esac
}
#}}}: main

main "$@"
