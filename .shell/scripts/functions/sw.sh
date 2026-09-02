#!/usr/bin/env bash
#
# sw — fzf branch switcher with bare+worktree support.
#
# Usage: sw [a|-a] [l|ls|-l] [c|n|-c|-n] [d|-d] [branch]
#   (none)  pick a branch and switch to it (worktree-aware)
#   -a      fetch all remotes and include remote branches in the picker
#   -l      list branches and exit
#   -c/-n   create a new branch (base picked via fzf, name from arg or prompt)
#   -d      delete a branch (and its worktree)
#   branch  skip the picker and use this branch name directly
#
# Prints a directory on stdout when the caller should cd there; everything
# else goes to stderr. The .zshrc wrapper turns a printed directory into cd.

set -euo pipefail

if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3))); then
  echo "sw: bash >= 4.3 required, found $BASH_VERSION" >&2
  exit 1
fi

if ! command -v fzf >/dev/null; then
  echo "sw: required command 'fzf' not found" >&2
  exit 1
fi

fetchAll=0 deleteBranch=0 gitList=0 createBranch=0 branch=""

for arg; do
  case $arg in
  'a' | '-a') fetchAll=1 ;;
  'd' | '-d') deleteBranch=1 ;;
  'ls' | 'l' | '-l') gitList=1 ;;
  [cn] | -[cn]) createBranch=1 ;;
  -*)
    echo "sw: unknown option '$arg'" >&2
    exit 1
    ;;
  *) branch="$arg" ;;
  esac
done

_msg() { #{{{
  echo "$*" >&2
}
#}}}: _msg

_die() { #{{{
  _msg "$*"
  exit 1
}
#}}}: _die

_prompt() { #{{{
  local yn
  read -n 1 -r -p ">> $1 [y/N]: " yn
  echo >&2
  [[ $yn == [yY] ]] || _die "Aborted."
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
  done < <(git worktree list --porcelain)
  return 0
}
#}}}: _worktreePath

_localName() { #{{{
  # origin/feat/x -> feat/x when it is a remote-tracking ref, otherwise unchanged
  local name="${1#remotes/}"
  if git show-ref --verify -q "refs/remotes/$name"; then
    echo "${name#*/}"
  else
    echo "$name"
  fi
}
#}}}: _localName

_branchExists() { #{{{
  git show-ref --verify -q "refs/heads/$1" ||
    git show-ref --verify -q "refs/remotes/origin/$1"
}
#}}}: _branchExists

_branches() { #{{{
  if ((fetchAll)); then
    git branch -a --format='%(refname)' |
      sed -e '/\/HEAD$/d' -e 's#^refs/heads/##' -e 's#^refs/remotes/##'
  elif [[ -n $barePath ]]; then
    # In a worktree setup only branches that already have a worktree
    git branch --format='%(if)%(worktreepath)%(then)%(refname:short)%(end)' |
      sed -e '/^$/d' -e '/^(HEAD/d'
  else
    git branch --format='%(refname:short)' | sed '/^(HEAD/d'
  fi
}
#}}}: _branches

_fzf() { #{{{
  fzf \
    --no-sort \
    --track \
    --ansi \
    --layout=reverse-list \
    --preview 'git log --oneline --decorate --color=always {}'
}
#}}}: _fzf

_pick() { #{{{
  local selected
  selected="$(_branches | _fzf)" || true
  [[ -n $selected ]] || _die "No branch selected!"
  echo "$selected"
}
#}}}: _pick

_addWorktree() { #{{{
  # $1 = branch, $2 = optional base; with a base a new branch is created.
  local name="$1" base="${2-}" dir
  dir="$repoRoot/$(_flatten "$name")"

  if [[ -n $base ]]; then
    git worktree add -b "$name" "$dir" "$base" >/dev/null ||
      _die "Failed to create worktree for '$name'."
  else
    git worktree add "$dir" "$name" >/dev/null ||
      _die "Failed to create worktree for '$name'."
  fi
  echo "$dir"
}
#}}}: _addWorktree

_rebaseOnto() { #{{{
  # Rebase the current branch on the remote counterpart of $1, if it has one.
  local base="$1" upstream
  if git show-ref --verify -q "refs/remotes/$base"; then
    upstream="$base"
  else
    upstream="$(git for-each-ref --format='%(upstream:short)' "refs/heads/$base")"
    # Many bare clones have no upstream configured; fall back to origin/<base>
    if [[ -z $upstream ]] && git show-ref --verify -q "refs/remotes/origin/$base"; then
      upstream="origin/$base"
    fi
  fi
  if [[ -z $upstream ]]; then
    _msg "No remote counterpart for '$base', skipping rebase."
    return 0
  fi
  git pull --rebase -q "${upstream%%/*}" "${upstream#*/}" >&2 ||
    _die "Rebase onto '$upstream' failed."
}
#}}}: _rebaseOnto

_create() { #{{{
  local base new dir
  base="$(_pick)"

  new="$branch"
  if [[ -z $new ]]; then
    read -r -p ">> New branch: " new
  fi
  [[ -n $new ]] || _die "Branch name cannot be empty!"

  if [[ -z $barePath ]]; then
    git checkout -b "$new" "$base" >&2
    return 0
  fi

  dir="$(_addWorktree "$new" "$base")"
  cd "$dir"
  _rebaseOnto "$base"
  echo "$dir"
}
#}}}: _create

_delete() { #{{{
  local target="$1" path default rc=0

  [[ $target == remotes/* ]] && _die "Cannot delete a remote branch."

  if [[ -n $barePath ]]; then
    default="$(git --git-dir="$barePath" symbolic-ref --short HEAD 2>/dev/null || true)"
    [[ $target == "$default" ]] && _die "Refusing to delete the default branch '$default'."
  fi

  _prompt "Delete branch: $target"

  path="$(_worktreePath "$target")"
  if [[ -n $path ]]; then
    # Leave the worktree before removing it so git never runs from a deleted cwd
    cd "$repoRoot"
    git worktree remove -f "$path" || rc=1
  fi
  git branch -D "$target" >/dev/null || rc=1
  ((rc == 0)) || _die "Failed to delete '$target'."

  [[ -n $barePath ]] && echo "$repoRoot"
  return 0
}
#}}}: _delete

_switch() { #{{{
  local name path current working
  name="$(_localName "$1")"

  if [[ -z $barePath ]]; then
    git switch "$name" >&2
    return 0
  fi

  path="$(_worktreePath "$name")"
  if [[ -z $path ]]; then
    _branchExists "$name" || _die "No such branch: '$name'."
    _addWorktree "$name"
    return 0
  fi

  # Preserve the nested directory when it also exists in the target worktree
  current="$(_worktreePath "$(git branch --show-current)")"
  if [[ -n $current && $PWD == "$current"/* ]]; then
    working="$path${PWD#"$current"}"
    if [[ -d $working ]]; then
      echo "$working"
      return 0
    fi
  fi
  echo "$path"
}
#}}}: _switch

barePath="$(_worktreePath "")"
repoRoot="${barePath%/*}"
readonly barePath repoRoot

((fetchAll && deleteBranch)) && _die "Cannot combine -a with -d."

if ((fetchAll)); then
  git fetch --all >&2
fi

if ((gitList)); then
  _branches
  exit 0
fi

if ((createBranch)); then
  _create
  exit 0
fi

target="${branch:-$(_pick)}"

if ((deleteBranch)); then
  _delete "$target"
  exit 0
fi

_switch "$target"
