#!/usr/bin/env bash
#
# sw — fzf branch switcher with bare+worktree support.
#
# Usage: sw [-a] [-l] [-c|-n] [-d] [-h] [branch] [base]
#   (none)     pick a branch and switch to it (worktree-aware)
#   branch     skip the picker; an unknown name offers to create it
#   -a         fetch --all --prune first (the picker always shows known remotes)
#   -l, ls     list branches and exit
#   -c, -n     create a branch: `sw -c`, `sw -c name`, `sw -c name base`
#   -d         delete branches (TAB multi-select); refuses the default branch
#   -h         this help
#
# Picker line: name  [worktree|local|remote] [merged] [gone]  ↑ahead ↓behind  age  subject
# Type "merged" or "gone" to filter. In switch mode, typing a name with no
# match and pressing Enter offers to create it from the default branch.
#
# Prints a directory on stdout when the caller should cd there; everything
# else goes to stderr. The .zshrc wrapper turns a printed directory into cd.

set -euo pipefail

if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
  echo "sw: bash >= 4.4 required, found $BASH_VERSION" >&2
  exit 1
fi

if ! command -v fzf >/dev/null; then
  echo "sw: required command 'fzf' not found" >&2
  exit 1
fi

fetchAll=0 deleteBranch=0 gitList=0 createBranch=0 showHelp=0 previewMode=0
branch="" base=""

for arg; do
  case $arg in
  'a' | '-a') fetchAll=1 ;;
  'd' | '-d') deleteBranch=1 ;;
  'ls' | 'l' | '-l') gitList=1 ;;
  [cn] | -[cn]) createBranch=1 ;;
  '-h' | '--help') showHelp=1 ;;
  '--preview') previewMode=1 ;;
  -*)
    echo "sw: unknown option '$arg' (try -h)" >&2
    exit 1
    ;;
  *)
    if [[ -z $branch ]]; then
      branch="$arg"
    elif [[ -z $base ]]; then
      base="$arg"
    else
      echo "sw: too many arguments (try -h)" >&2
      exit 1
    fi
    ;;
  esac
done

# ---------------------------------------------------------------- helpers

# shellcheck source=../lib/worktree.sh
source "${BASH_SOURCE[0]%/*}/../lib/worktree.sh"

C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_DIM=$'\e[2m'
C_GREEN=$'\e[32m' C_RED=$'\e[31m' C_YELLOW=$'\e[33m' C_BLUE=$'\e[34m' C_MAGENTA=$'\e[35m'



_usage() { #{{{
  sed -n '/^# Usage/,/^$/p' "$0" | sed -e 's/^# \{0,1\}//' -e '/^$/d'
}
#}}}: _usage




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

_hasLocal() { #{{{
  git show-ref --verify -q "refs/heads/$1"
}
#}}}: _hasLocal

_hasRemote() { #{{{
  git show-ref --verify -q "refs/remotes/origin/$1"
}
#}}}: _hasRemote

_branchExists() { #{{{
  _hasLocal "$1" || _hasRemote "$1"
}
#}}}: _branchExists

_logRef() { #{{{
  # A ref `git log` understands for a branch that may be remote-only
  if _hasLocal "$1"; then echo "$1"; else echo "origin/$1"; fi
}
#}}}: _logRef

_defaultBranch() { #{{{
  local d=""
  if [[ -n $barePath ]]; then
    d="$(git --git-dir="$barePath" symbolic-ref --short HEAD 2>/dev/null || true)"
  fi
  if [[ -z $d ]]; then
    d="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    d="${d#origin/}"
  fi
  if [[ -z $d ]]; then
    local c
    for c in main master; do
      if _hasLocal "$c"; then d="$c"; break; fi
    done
  fi
  echo "$d"
}
#}}}: _defaultBranch

_dirtyCount() { #{{{
  git -C "$1" status --porcelain 2>/dev/null | wc -l | tr -d ' '
}
#}}}: _dirtyCount

_age() { #{{{
  # Sets REPLY: "3 days ago" -> 3d, "1 year, 2 months ago" -> 1y
  local n="${1%% *}" unit="${1#* }"
  unit="${unit%% *}"
  case $unit in
  second*) REPLY="now" ;;
  minute*) REPLY="${n}m" ;;
  hour*) REPLY="${n}h" ;;
  day*) REPLY="${n}d" ;;
  week*) REPLY="${n}w" ;;
  month*) REPLY="${n}mo" ;;
  year*) REPLY="${n}y" ;;
  *) REPLY="$1" ;;
  esac
}
#}}}: _age

_track() { #{{{
  # $1 = name, $2 = upstream:track text ("ahead 2, behind 1", "gone", ""),
  # $3 = upstream ref (empty when none), $4 = local sha, $5 = origin/<name> sha
  # (empty when absent). Sets REPLY to "↑N ↓M", "gone" or "".
  local name="$1" text="$2" upstream="$3" localSha="$4" remoteSha="$5"
  local ahead="" behind="" counts
  REPLY=""
  if [[ $text == gone ]]; then
    REPLY="gone"
    return 0
  fi
  if [[ -n $text ]]; then
    [[ $text =~ ahead\ ([0-9]+) ]] && ahead="${BASH_REMATCH[1]}"
    [[ $text =~ behind\ ([0-9]+) ]] && behind="${BASH_REMATCH[1]}"
  elif [[ -z $upstream && -n $remoteSha && $remoteSha != "$localSha" ]]; then
    # No upstream configured and origin/<name> differs: count the divergence.
    # Equal shas (the common case after a bare clone) cost nothing.
    counts="$(git rev-list --left-right --count "$name...origin/$name" 2>/dev/null || true)"
    ahead="${counts%%[[:space:]]*}"
    behind="${counts##*[[:space:]]}"
    [[ $ahead == 0 ]] && ahead=""
    [[ $behind == 0 ]] && behind=""
  fi
  REPLY="${ahead:+↑$ahead}${ahead:+${behind:+ }}${behind:+↓$behind}"
}
#}}}: _track

_pad() { #{{{
  # Sets REPLY to $1 right-padded with spaces to $2 characters (multibyte safe)
  REPLY="$1"
  while ((${#REPLY} < $2)); do REPLY+=" "; done
}
#}}}: _pad

_branchTable() { #{{{
  # Emits one line per branch, newest commit first:  name<TAB>display
  # display = "name  tags  track  age  subject", aligned, with ANSI colors.
  # $1 = branch to put first (used to preselect a base).
  local front="${1-}"
  local -a names tagList trackList ageList subjectList
  local -A isLocal isRemote isMerged
  local ref sha wt upstream track date subject name kind tagText
  local n=0 nameWidth=0 tagWidth=0 trackWidth=0

  while IFS= read -r name; do isLocal[$name]=1; done \
    < <(git branch --format='%(refname:short)' | sed '/^(HEAD/d')
  local sha
  while read -r name sha; do isRemote[${name#origin/}]="$sha"; done \
    < <(git for-each-ref --format='%(refname:short) %(objectname)' refs/remotes/origin | sed '/^origin /d')

  if [[ -n $defaultBranch ]]; then
    while IFS= read -r name; do
      name="${name#origin/}"
      [[ $name == "$defaultBranch" || $name == origin ]] && continue
      isMerged[$name]=1
    done < <(
      git branch --format='%(refname:short)' --merged "$defaultBranch" 2>/dev/null
      git branch -r --format='%(refname:short)' --merged "$defaultBranch" 2>/dev/null
    )
  fi

  while IFS=$'\x1f' read -r ref sha wt upstream track date subject; do
    case $ref in
    refs/heads/*)
      name="${ref#refs/heads/}"
      if [[ -n $wt && -n $barePath ]]; then kind="worktree"; else kind="local"; fi
      _track "$name" "$track" "$upstream" "$sha" "${isRemote[$name]-}"
      ;;
    refs/remotes/origin/HEAD) continue ;;
    refs/remotes/origin/*)
      name="${ref#refs/remotes/origin/}"
      [[ -n ${isLocal[$name]-} ]] && continue
      kind="remote"
      REPLY=""
      ;;
    *) continue ;;
    esac
    track="$REPLY"

    tagText="$kind"
    [[ -n ${isMerged[$name]-} ]] && tagText+=" merged"
    if [[ $track == gone ]]; then
      tagText+=" gone"
      track=""
    fi

    _age "$date"
    names[n]="$name" tagList[n]="$tagText" trackList[n]="$track"
    ageList[n]="$REPLY" subjectList[n]="${subject:0:60}"
    ((${#name} > nameWidth && ${#name} <= 48)) && nameWidth=${#name}
    ((${#tagText} > tagWidth)) && tagWidth=${#tagText}
    ((${#track} > trackWidth)) && trackWidth=${#track}
    n=$((n + 1))
  done < <(git for-each-ref --sort=-committerdate \
    --format='%(refname)%1f%(objectname)%1f%(worktreepath)%1f%(upstream:short)%1f%(upstream:track,nobracket)%1f%(committerdate:relative)%1f%(subject)' \
    refs/heads refs/remotes/origin)

  local i mark padName padTags padTrack
  local -a order=()
  for ((i = 0; i < n; i++)); do
    if [[ ${names[i]} == "$front" ]]; then
      order=("$i" "${order[@]+"${order[@]}"}")
    else
      order+=("$i")
    fi
  done

  for i in "${order[@]+"${order[@]}"}"; do
    name="${names[i]}"
    mark=" "
    [[ $name == "$currentBranch" ]] && mark="*"
    _pad "$name" "$nameWidth"; padName="$REPLY"
    _pad "${tagList[i]}" "$tagWidth"; padTags="$REPLY"
    _pad "${trackList[i]}" "$trackWidth"; padTrack="$REPLY"

    padTags="${padTags//worktree/${C_GREEN}worktree${C_RESET}}"
    padTags="${padTags//local/${C_BLUE}local${C_RESET}}"
    padTags="${padTags//remote/${C_MAGENTA}remote${C_RESET}}"
    padTags="${padTags//merged/${C_YELLOW}merged${C_RESET}}"
    padTags="${padTags//gone/${C_RED}gone${C_RESET}}"
    padTrack="${padTrack//↑/${C_GREEN}↑}"
    padTrack="${padTrack//↓/${C_RED}↓}"

    printf '%s\t%s%s%s%s  %s  %s%s  %s%4s%s  %s%s%s\n' \
      "$name" \
      "$C_BOLD" "$mark" "$padName" "$C_RESET" \
      "$padTags" \
      "$padTrack" "$C_RESET" \
      "$C_DIM" "${ageList[i]}" "$C_RESET" \
      "$C_DIM" "${subjectList[i]}" "$C_RESET"
  done
}
#}}}: _branchTable

_fzf() { #{{{
  # Shows and searches the display column; callers cut -f1 for the name.
  fzf \
    --exact \
    --ansi \
    --no-sort \
    --track \
    --layout=reverse-list \
    --delimiter=$'\t' \
    --with-nth=2 \
    --preview "'$0' --preview {1}" \
    --preview-window="right:40%,wrap,<120(down:40%)" \
    "$@"
}
#}}}: _fzf

_preview() { #{{{
  local name="$1" path dirty
  name="${name%%[[:space:]]*}"
  path="$(_worktreePath "$name")"

  if [[ -n $path ]]; then
    dirty="$(_dirtyCount "$path")"
    printf '%sworktree%s %s' "$C_BOLD" "$C_RESET" "$path"
    if ((dirty > 0)); then
      printf ' %s(%s uncommitted)%s\n' "$C_YELLOW" "$dirty" "$C_RESET"
      git -C "$path" -c color.status=always status --short | head -20
    else
      printf ' %s(clean)%s\n' "$C_GREEN" "$C_RESET"
    fi
    echo
  elif ! _hasLocal "$name"; then
    printf '%sremote only%s origin/%s\n\n' "$C_MAGENTA" "$C_RESET" "$name"
  fi

  git log --oneline --decorate --color=always -n 40 "$(_logRef "$name")" 2>/dev/null ||
    echo "(no commits)"
}
#}}}: _preview

_header() { #{{{
  local where="$currentBranch"
  [[ -z $where ]] && where="(detached)"
  echo "on ${where}  ·  ${repoRoot:-$PWD}${1:+  ·  $1}"
}
#}}}: _header

_pickOne() { #{{{
  # $1 = branch to put first (optional), $2 = header hint (optional)
  local selected
  selected="$(_branchTable "${1-}" | _fzf --header "$(_header "${2-}")" | head -n1 | cut -f1)" || true
  [[ -n $selected ]] || _die "No branch selected!"
  echo "$selected"
}
#}}}: _pickOne

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
    if [[ -z $upstream ]] && _hasRemote "$base"; then
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

_createBranch() { #{{{
  # $1 = new name, $2 = base. Prints the new worktree path in worktree setups.
  local new="$1" from="$2" dir

  if [[ -z $barePath ]]; then
    git checkout -b "$new" "$from" >&2
    return 0
  fi

  dir="$(_addWorktree "$new" "$from")"
  cd "$dir"
  _rebaseOnto "$from"
  echo "$dir"
}
#}}}: _createBranch

_create() { #{{{
  local from="$base" new="$branch"

  if [[ -z $from ]]; then
    from="$(_pickOne "$defaultBranch" "pick the BASE branch")"
  fi
  _branchExists "$from" || _die "No such base branch: '$from'."

  if [[ -z $new ]]; then
    read -r -p ">> New branch (from $from): " new
  fi
  [[ -n $new ]] || _die "Branch name cannot be empty!"
  _hasLocal "$new" && _die "Branch '$new' already exists."

  _createBranch "$new" "$from"
}
#}}}: _create

_delete() { #{{{
  local -a targets=("$@")
  local t path dirty summary="" leaving=0 rc=0

  ((${#targets[@]})) || _die "No branch selected!"

  for t in "${targets[@]}"; do
    [[ $t == "$defaultBranch" ]] && _die "Refusing to delete the default branch '$t'."
    _hasLocal "$t" || _die "'$t' is not a local branch (remote branches are not deleted)."
    path="$(_worktreePath "$t")"
    summary+="   $t"
    if [[ -n $path ]]; then
      dirty="$(_dirtyCount "$path")"
      summary+="  (worktree"
      ((dirty > 0)) && summary+=", ${C_YELLOW}${dirty} uncommitted change(s)${C_RESET}"
      summary+=")"
      [[ $PWD == "$path" || $PWD == "$path"/* ]] && leaving=1
    fi
    summary+=$'\n'
  done

  _msg "Branches to delete:"
  printf '%s' "$summary" >&2
  _prompt "Delete ${#targets[@]} branch(es)?"

  # Leave any worktree before removing it so git never runs from a deleted cwd
  [[ -n $repoRoot ]] && cd "$repoRoot"

  for t in "${targets[@]}"; do
    path="$(_worktreePath "$t")"
    if [[ -n $path ]]; then
      git worktree remove -f "$path" || { rc=1; continue; }
    fi
    git branch -D "$t" >/dev/null || rc=1
  done
  ((rc == 0)) || _die "Some branches could not be deleted."

  ((leaving)) && echo "$repoRoot"
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
  current="$(_worktreePath "$currentBranch")"
  if [[ -n $current && $PWD == "$current"/* ]]; then
    working="$path${PWD#"$current"}"
    if [[ -d $working ]]; then
      echo "$working"
      return 0
    fi
    _msg "'${PWD#"$current"/}' does not exist in $(basename "$path"), landing at its root."
  fi
  echo "$path"
}
#}}}: _switch

_offerCreate() { #{{{
  local new="$1"
  [[ -n $defaultBranch ]] || _die "No such branch: '$new'."
  _prompt "No branch '$new'. Create it from '$defaultBranch'?"
  _createBranch "$new" "$defaultBranch"
}
#}}}: _offerCreate

# ---------------------------------------------------------------- main

if ((showHelp)); then
  _usage
  exit 0
fi

barePath="$(_worktreePath "")"
repoRoot="${barePath%/*}"
currentBranch="$(git branch --show-current 2>/dev/null || true)"
defaultBranch="$(_defaultBranch)"
readonly barePath repoRoot currentBranch defaultBranch

if ((previewMode)); then
  _preview "$branch"
  exit 0
fi

((fetchAll && deleteBranch)) && _die "Cannot combine -a with -d."

if [[ -n $barePath ]]; then
  git worktree prune -v 2>&1 | sed 's/^/sw: pruned stale worktree: /' >&2 || true
fi

if ((fetchAll)); then
  _msg "Fetching all remotes..."
  git fetch --all --prune >&2
fi

if ((gitList)); then
  if [[ -t 1 ]]; then
    _branchTable | cut -f2
  else
    _branchTable | cut -f2 | sed $'s/\e\\[[0-9;]*m//g'
  fi
  exit 0
fi

if ((createBranch)); then
  _create
  exit 0
fi

if ((deleteBranch)); then
  if [[ -n $branch ]]; then
    _delete "$branch"
  else
    mapfile -t picked < <(
      _branchTable | _fzf --multi --header "$(_header "TAB: multi  ·  filter: merged, gone")" | cut -f1
    )
    _delete "${picked[@]+"${picked[@]}"}"
  fi
  exit 0
fi

# Switch mode. A positional name is used directly; otherwise pick, and let a
# typed name with no match create a new branch.
if [[ -n $branch ]]; then
  if _branchExists "$(_localName "$branch")"; then
    _switch "$branch"
  else
    _offerCreate "$branch"
  fi
  exit 0
fi

rc=0
out="$(_branchTable | awk -F'\t' -v cur="$currentBranch" '$1 != cur' |
  _fzf --print-query --header "$(_header "Enter: switch  ·  new name: create from $defaultBranch")")" || rc=$?

query="${out%%$'\n'*}"
selected="$(printf '%s\n' "$out" | sed -n '2p' | cut -f1)"

case $rc in
0) _switch "$selected" ;;
1)
  # fzf: no match for the query
  [[ -n $query ]] || _die "No branch selected!"
  _offerCreate "$query"
  ;;
*) _die "No branch selected!" ;;
esac
