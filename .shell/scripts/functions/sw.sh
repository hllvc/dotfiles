#!/usr/bin/env bash
#
# sw — fzf branch switcher with bare+worktree support.
#
# Usage: sw [-a] [-l] [-L] [-c|-n] [-d] [-h] [branch] [base]
#   (none)     pick a branch and switch to it (worktree-aware)
#   branch     skip the picker; an unknown name offers to create it
#   -          switch back to the previous branch
#   -a         fetch --all --prune first (the picker always shows known remotes)
#   -l, ls     list branches and exit
#   -L         local branches only (hide remote-only refs)
#   -c, -n     create a branch: `sw -c`, `sw -c name`, `sw -c name base`
#   --no-rebase  skip the rebase onto the base's remote after -c
#   -d         delete branches (TAB multi-select); refuses the default branch
#   st         status of every worktree: dirty, ahead/behind, carry
#   carry      gitignored local files carried into every worktree:
#              `sw carry` picker (link/copy/detach/forget), `sw carry ls|apply`,
#              `sw carry diff|reset|edit [path]`
#   -h         this help
#
# Picker keys: Enter switch  ctrl-x delete  ctrl-o create from highlighted
#              ctrl-f fetch + reload  ctrl-r reload
#   carry:     ctrl-s link  ctrl-o copy  ctrl-x detach  ctrl-f forget
#
# Config (git config, e.g. in .bare/config):
#   sw.remote      remote to track (default origin)
#   sw.rebase      false = never rebase after -c
#   sw.postCreate  shell command run inside every new worktree
#
# Picker line: name  [worktree|local|remote] [merged] [gone] [recent]  ↑ahead ↓behind  age  subject
# In switch mode, typing a name with no match and pressing Enter offers to
# create it from the default branch.
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

fetchAll=0 deleteBranch=0 gitList=0 createBranch=0 showHelp=0 previewMode=0 carryMode=0
tableMode=0 statusMode=0 goBack=0 localOnly=0 noRebase=0
branch="" base=""

for arg; do
  case $arg in
  'a' | '-a') fetchAll=1 ;;
  'd' | '-d') deleteBranch=1 ;;
  'ls' | 'l' | '-l') gitList=1 ;;
  '-L') localOnly=1 ;;
  [cn] | -[cn]) createBranch=1 ;;
  '--no-rebase') noRebase=1 ;;
  '-h' | '--help') showHelp=1 ;;
  '--preview') previewMode=1 ;;
  '--table') tableMode=1 ;;
  'st' | 'status') statusMode=1 ;;
  'carry') carryMode=1 ;;
  '-') goBack=1 ;;
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
  sed -n '/^# Usage/,/^# Picker line/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'
}
#}}}: _usage

_cfg() { #{{{
  # $1 = key (without sw.), $2 = default. Read through the normal git config
  # chain, so .bare/config, ~/.gitconfig and the environment all work.
  git config --get "sw.$1" 2>/dev/null || echo "${2-}"
}
#}}}: _cfg

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
  git show-ref --verify -q "refs/remotes/$remote/$1"
}
#}}}: _hasRemote

_branchExists() { #{{{
  _hasLocal "$1" || _hasRemote "$1"
}
#}}}: _branchExists

_logRef() { #{{{
  # A ref `git log` understands for a branch that may be remote-only
  if _hasLocal "$1"; then echo "$1"; else echo "$remote/$1"; fi
}
#}}}: _logRef

_recentFile() { #{{{
  echo "${barePath:-$(git rev-parse --git-common-dir 2>/dev/null)}/sw.recent"
}
#}}}: _recentFile

_recent() { #{{{
  # Branches visited most recently first (stale names are filtered by callers)
  cat "$(_recentFile)" 2>/dev/null || true
}
#}}}: _recent

_recentAdd() { #{{{
  # Put $@ in front of the recent list (first argument ends up first), max 20
  local f tmp
  f="$(_recentFile)"
  [[ -d ${f%/*} ]] || return 0
  tmp="$(printf '%s\n' "$@"; _recent)"
  printf '%s\n' "$tmp" | awk 'NF && !seen[$0]++' | head -n 20 >"$f.tmp" && mv "$f.tmp" "$f"
}
#}}}: _recentAdd

_recentDrop() { #{{{
  local f
  f="$(_recentFile)"
  [[ -f $f ]] || return 0
  _recent | awk -v drop="$1" '$0 != drop' >"$f.tmp" && mv "$f.tmp" "$f"
}
#}}}: _recentDrop

_previousBranch() { #{{{
  # Most recently visited branch other than the current one that still exists
  local b
  while IFS= read -r b; do
    [[ $b == "$currentBranch" ]] && continue
    _branchExists "$b" && { echo "$b"; return 0; }
  done < <(_recent)
  return 1
}
#}}}: _previousBranch

_defaultBranch() { #{{{
  local d=""
  if [[ -n $barePath ]]; then
    d="$(git --git-dir="$barePath" symbolic-ref --short HEAD 2>/dev/null || true)"
  fi
  if [[ -z $d ]]; then
    d="$(git symbolic-ref --short "refs/remotes/$remote/HEAD" 2>/dev/null || true)"
    d="${d#"$remote"/}"
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
    # No upstream configured and <remote>/<name> differs: count the divergence.
    # Equal shas (the common case after a bare clone) cost nothing.
    counts="$(git rev-list --left-right --count "$name...$remote/$name" 2>/dev/null || true)"
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
  local -A isLocal isRemote isMerged index
  local ref sha wt upstream track date subject name kind tagText
  local n=0 nameWidth=0 tagWidth=0 trackWidth=0

  while IFS= read -r name; do isLocal[$name]=1; done \
    < <(git branch --format='%(refname:short)' | sed '/^(HEAD/d')
  local sha
  while read -r name sha; do isRemote[${name#"$remote"/}]="$sha"; done \
    < <(git for-each-ref --format='%(refname:short) %(objectname)' "refs/remotes/$remote" | sed "/^$remote /d")

  if [[ -n $defaultBranch ]]; then
    while IFS= read -r name; do
      name="${name#"$remote"/}"
      [[ $name == "$defaultBranch" || $name == "$remote" ]] && continue
      isMerged[$name]=1
    done < <(
      git branch --format='%(refname:short)' --merged "$defaultBranch" 2>/dev/null
      git branch -r --format='%(refname:short)' --merged "$defaultBranch" 2>/dev/null
    )
  fi

  local -a refDirs=(refs/heads)
  ((localOnly)) || refDirs+=("refs/remotes/$remote")

  while IFS=$'\x1f' read -r ref sha wt upstream track date subject; do
    case $ref in
    refs/heads/*)
      name="${ref#refs/heads/}"
      if [[ -n $wt && -n $barePath ]]; then kind="worktree"; else kind="local"; fi
      _track "$name" "$track" "$upstream" "$sha" "${isRemote[$name]-}"
      ;;
    "refs/remotes/$remote/HEAD") continue ;;
    "refs/remotes/$remote/"*)
      name="${ref#refs/remotes/"$remote"/}"
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
    index[$name]=$n
    ((${#name} > nameWidth && ${#name} <= 48)) && nameWidth=${#name}
    ((${#track} > trackWidth)) && trackWidth=${#track}
    n=$((n + 1))
  done < <(git for-each-ref --sort=-committerdate \
    --format='%(refname)%1f%(objectname)%1f%(worktreepath)%1f%(upstream:short)%1f%(upstream:track,nobracket)%1f%(committerdate:relative)%1f%(subject)' \
    "${refDirs[@]}")

  # Order: the requested front branch, then recently visited ones, then by date
  local i mark padName padTags padTrack
  local -a order=()
  local -A placed
  if [[ -n $front && -n ${index[$front]-} ]]; then
    order+=("${index[$front]}"); placed[$front]=1
  fi
  while IFS= read -r name; do
    [[ -n ${index[$name]-} && -z ${placed[$name]-} && $name != "$currentBranch" ]] || continue
    order+=("${index[$name]}"); placed[$name]=1
    i="${index[$name]}"; tagList[i]+=" recent"
  done < <(_recent)
  for ((i = 0; i < n; i++)); do
    [[ -n ${placed[${names[i]}]-} ]] || order+=("$i")
  done
  for ((i = 0; i < n; i++)); do
    ((${#tagList[i]} > tagWidth)) && tagWidth=${#tagList[i]}
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
    padTags="${padTags//recent/${C_DIM}recent${C_RESET}}"
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
    _carryCounts "$path"
    [[ -n $REPLY ]] && printf '%scarry%s %s\n' "$C_BOLD" "$C_RESET" "$REPLY"
    echo
  elif ! _hasLocal "$name"; then
    printf '%sremote only%s %s/%s\n\n' "$C_MAGENTA" "$C_RESET" "$remote" "$name"
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
  # feat/x and feat-x flatten to the same directory
  [[ -e $dir ]] && _die "'$dir' already exists (another branch flattens to the same directory?)."

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
    # Many bare clones have no upstream configured; fall back to <remote>/<base>
    if [[ -z $upstream ]] && _hasRemote "$base"; then
      upstream="$remote/$base"
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

_offerMoveChanges() { #{{{
  # Offer to take the uncommitted changes of worktree $1 along to a new one.
  # Prints the path of a patch holding them (empty when declined or clean).
  local dirty patch
  dirty="$(_dirtyCount "$1")"
  ((dirty > 0)) || return 0
  _ask "Move $dirty uncommitted change(s) from $(basename "$1") into the new worktree?" || return 0
  patch="$(mktemp "${TMPDIR:-/tmp}/sw-move.XXXXXX")"
  # Intent-to-add makes untracked files part of the diff; staged and unstaged
  # changes end up together, which is what a fresh worktree needs anyway.
  git -C "$1" add -A -N
  git -C "$1" diff --binary HEAD >"$patch"
  git -C "$1" reset -q
  echo "$patch"
}
#}}}: _offerMoveChanges

_applyMovedChanges() { #{{{
  # $1 = source worktree, $2 = new worktree, $3 = patch from _offerMoveChanges
  # Plain apply first (a fresh worktree matches the patch exactly); fall back
  # to a three-way merge when the rebase moved the base.
  if ! git -C "$2" apply --whitespace=nowarn "$3" 2>/dev/null &&
    ! git -C "$2" apply --3way --whitespace=nowarn "$3" >&2; then
    _msg "Could not apply the changes in $(basename "$2"); they stay in $(basename "$1"), patch kept at $3."
    return 0
  fi
  if git -C "$1" apply -R --whitespace=nowarn "$3" >&2; then
    rm -f "$3"
    _msg "Moved the uncommitted changes into $(basename "$2")."
  else
    _msg "Changes applied in $(basename "$2") but not removed from $(basename "$1"); patch kept at $3."
  fi
}
#}}}: _applyMovedChanges

_postCreate() { #{{{
  # Run the sw.postCreate command inside the new worktree $1, if configured.
  local cmd rc=0
  cmd="$(_cfg postCreate)"
  [[ -n $cmd ]] || return 0
  _msg "postCreate: $cmd"
  (cd "$1" && bash -c "$cmd" >&2) || rc=$?
  ((rc == 0)) || _msg "postCreate failed (exit $rc), worktree kept."
}
#}}}: _postCreate

_createBranch() { #{{{
  # $1 = new name, $2 = base. Prints the new worktree path in worktree setups.
  local new="$1" from="$2" dir srcWt="" patch=""

  if [[ -z $barePath ]]; then
    git checkout -b "$new" "$from" >&2
    _recentAdd "$new" "$currentBranch"
    return 0
  fi

  srcWt="$(_worktreePath "$currentBranch")"
  [[ -n $srcWt && ($PWD == "$srcWt" || $PWD == "$srcWt"/*) ]] && patch="$(_offerMoveChanges "$srcWt")"

  dir="$(_addWorktree "$new" "$from")"
  cd "$dir"
  if ((noRebase)) || [[ "$(_cfg rebase true)" == false ]]; then
    :
  else
    _rebaseOnto "$from"
  fi
  [[ -n $patch ]] && _applyMovedChanges "$srcWt" "$dir" "$patch"
  _afterWorktreeCreated "$dir" "$(_baseWorktree "$from")"
  _postCreate "$dir"
  _recentAdd "$new" "$currentBranch"
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
  local t p path dirty unpushed summary="" leaving=0 rc=0

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
    # Commits reachable from the branch but from no remote-tracking ref are lost with it
    unpushed="$(git rev-list --count "$t" --not --remotes 2>/dev/null || echo 0)"
    ((unpushed > 0)) && summary+="  ${C_RED}${unpushed} commit(s) not on any remote${C_RESET}"
    if [[ -n $path ]]; then
      while IFS= read -r p; do
        summary+=$'\n'"      ${C_YELLOW}local copy of '$p' differs from the store and will be lost${C_RESET}"
      done < <(_carryDivergent "$path")
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
    _recentDrop "$t"
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
    _recentAdd "$name" "$currentBranch"
    return 0
  fi

  path="$(_worktreePath "$name")"
  if [[ -z $path ]]; then
    _branchExists "$name" || _die "No such branch: '$name'."
    path="$(_addWorktree "$name")"
    _afterWorktreeCreated "$path" "$(_baseWorktree "")"
    _postCreate "$path"
    _recentAdd "$name" "$currentBranch"
    echo "$path"
    return 0
  fi
  _recentAdd "$name" "$currentBranch"

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

_plain() { #{{{
  # Strip ANSI colors unless a terminal is attached (stdout is captured by the
  # .zshrc wrapper, so stderr is the tty check that works)
  if [[ -t 2 ]]; then cat; else sed $'s/\e\\[[0-9;]*m//g'; fi
}
#}}}: _plain

_status() { #{{{
  # One line per worktree: branch, dirty count, ahead/behind, carry, path
  local wt br dirty upstream track sha remoteSha mark width=0 i
  local -a wts=() brs=()
  while IFS=$'\t' read -r wt br; do
    wts+=("$wt"); brs+=("$br")
    ((${#br} > width)) && width=${#br}
  done < <(_worktrees)
  ((${#wts[@]})) || _die "No worktrees."

  for ((i = 0; i < ${#wts[@]}; i++)); do
    wt="${wts[i]}" br="${brs[i]}"
    mark=" "
    [[ $br == "$currentBranch" ]] && mark="*"
    dirty="$(_dirtyCount "$wt")"
    IFS=$'\x1f' read -r upstream track sha < <(git for-each-ref \
      --format='%(upstream:short)%1f%(upstream:track,nobracket)%1f%(objectname)' "refs/heads/$br")
    remoteSha="$(git rev-parse -q --verify "refs/remotes/$remote/$br" 2>/dev/null || true)"
    _track "$br" "$track" "$upstream" "$sha" "$remoteSha"
    track="$REPLY"
    [[ $track == gone ]] && track="${C_RED}gone${C_RESET}"
    track="${track//↑/${C_GREEN}↑}"
    track="${track//↓/${C_RED}↓}"
    _pad "$br" "$width"
    printf '%s%s%s%s  ' "$C_BOLD" "$mark" "$REPLY" "$C_RESET"
    if ((dirty > 0)); then printf '%s%3s uncommitted%s' "$C_YELLOW" "$dirty" "$C_RESET"
    else printf '%s%15s%s' "$C_GREEN" clean "$C_RESET"; fi
    printf '  %s%s' "$track" "$C_RESET"
    _carryCounts "$wt"
    [[ -n $REPLY ]] && printf '  carry: %s' "$REPLY"
    printf '  %s%s%s\n' "$C_DIM" "$wt" "$C_RESET"
  done
}
#}}}: _status

# ---------------------------------------------------------------- carry
# Gitignored local files (tfvars, .env, ...) carried into every worktree.
# Store:  <repo>/.local/<relpath>, beside .bare, never seen by git.
# Config: repeated `sw.carry` values in .bare/config, "link:<path>" or
#         "copy:<path>"; the value "none" means "asked, nothing chosen".
# link = relative symlink into the store (shared, edit once);
# copy = per-worktree copy seeded from the store (free to diverge).

_carryStore() { #{{{
  echo "$repoRoot/.local"
}
#}}}: _carryStore

_carryCfg() { #{{{
  git config --file "$barePath/config" "$@"
}
#}}}: _carryCfg

_carryEntries() { #{{{
  # Prints "mode<TAB>path" per configured entry (the none sentinel is skipped)
  local e
  while IFS= read -r e; do
    case $e in
    link:* | copy:*) printf '%s\t%s\n' "${e%%:*}" "${e#*:}" ;;
    esac
  done < <(_carryCfg --get-all sw.carry 2>/dev/null || true)
}
#}}}: _carryEntries

_carryHasEntries() { #{{{
  [[ -n "$(_carryEntries)" ]]
}
#}}}: _carryHasEntries

_carryAsked() { #{{{
  _carryCfg --get-all sw.carry >/dev/null 2>&1
}
#}}}: _carryAsked

_carrySet() { #{{{
  # $1 = link|copy, $2 = path. Replaces any existing entry for the path.
  _carryForget "$2"
  _carryCfg --fixed-value --unset-all sw.carry none 2>/dev/null || true
  _carryCfg --add sw.carry "$1:$2"
}
#}}}: _carrySet

_carryForget() { #{{{
  local m
  for m in link copy; do
    _carryCfg --fixed-value --unset-all sw.carry "$m:$1" 2>/dev/null || true
  done
}
#}}}: _carryForget

_carryMarkNone() { #{{{
  _carryAsked || _carryCfg --add sw.carry none
}
#}}}: _carryMarkNone

_carryStatus() { #{{{
  # $1 = worktree, $2 = path, $3 = configured mode or "". Sets REPLY to
  # link | copy | detached | missing (carried, absent here) |
  # - (present, not carried) | elsewhere (not carried, only in other worktrees)
  local f="$1/$2" mode="$3"
  if [[ -L $f ]]; then
    REPLY="link"
  elif [[ -e $f ]]; then
    case $mode in
    link) REPLY="detached" ;;
    copy) REPLY="copy" ;;
    *) REPLY="-" ;;
    esac
  elif [[ -n $mode ]]; then
    REPLY="missing"
  else
    REPLY="elsewhere"
  fi
}
#}}}: _carryStatus

_carryLinkTarget() { #{{{
  # Absolute path a symlink $1 points to (no full resolution needed)
  local t
  t="$(readlink "$1")"
  [[ $t == /* ]] || t="${1%/*}/$t"
  echo "$t"
}
#}}}: _carryLinkTarget

_carryLinkInto() { #{{{
  # Make $1/$2 a relative symlink to the store. Returns 1 when skipped.
  local f="$1/$2" store rel
  store="$(_carryStore)/$2"
  [[ -e $store ]] || { _msg "carry: '$2' is missing from the store, skipped."; return 1; }
  rel="$(_relpath "${f%/*}" "$store")"
  if [[ -L $f ]]; then
    [[ "$(readlink "$f")" == "$rel" || "$(_carryLinkTarget "$f")" == "$store" ]] && return 0
    rm "$f"
  elif [[ -e $f ]]; then
    if cmp -s "$f" "$store"; then
      rm "$f"
    else
      _msg "carry: '$2' differs from the store, left as a detached copy."
      return 1
    fi
  fi
  mkdir -p "${f%/*}"
  ln -s "$rel" "$f"
}
#}}}: _carryLinkInto

_carryCopyInto() { #{{{
  # Copy the store file to $1/$2 unless a real file is already there.
  local f="$1/$2" store
  store="$(_carryStore)/$2"
  [[ -e $store ]] || { _msg "carry: '$2' is missing from the store, skipped."; return 1; }
  if [[ -L $f ]]; then
    rm "$f"
  elif [[ -e $f ]]; then
    return 0
  fi
  mkdir -p "${f%/*}"
  cp -p "$store" "$f"
}
#}}}: _carryCopyInto

_carryDetach() { #{{{
  # Replace the symlink $1/$2 with a real copy of its current content.
  local f="$1/$2" target
  [[ -L $f ]] || { _msg "carry: '$2' is not a link here."; return 1; }
  target="$(_carryLinkTarget "$f")"
  [[ -e $target ]] || { _msg "carry: '$2' is a dangling link, left alone."; return 1; }
  rm "$f"
  cp -p "$target" "$f"
}
#}}}: _carryDetach

_carrySeedStore() { #{{{
  # Ensure the store has $2, taking it from worktree $1 when absent.
  # $3 = link moves the file (and links it back), copy keeps the original.
  local src="$1/$2" store
  store="$(_carryStore)/$2"
  if [[ ! -e $store ]]; then
    [[ -f $src && ! -L $src ]] || _die "carry: '$2' is not a regular file in $1, cannot seed the store."
    mkdir -p "${store%/*}"
    if [[ $3 == link ]]; then mv "$src" "$store"; else cp -p "$src" "$store"; fi
  fi
  if [[ $3 == link ]]; then _carryLinkInto "$1" "$2" || true; fi
}
#}}}: _carrySeedStore

_carryApply() { #{{{
  # Apply every configured entry to worktree $1; one summary line on stderr.
  local m p linked=0 copied=0 skipped=0 extra=""
  while IFS=$'\t' read -r m p; do
    if [[ $m == link ]]; then
      if _carryLinkInto "$1" "$p"; then linked=$((linked + 1)); else skipped=$((skipped + 1)); fi
    else
      if _carryCopyInto "$1" "$p"; then copied=$((copied + 1)); else skipped=$((skipped + 1)); fi
    fi
  done < <(_carryEntries)
  ((linked + copied + skipped)) || return 0
  ((skipped)) && extra=", $skipped skipped"
  _msg "carried $((linked + copied)) file(s) into $(basename "$1") ($linked linked, $copied copied$extra)"
}
#}}}: _carryApply

_carryCounts() { #{{{
  # Sets REPLY to "N ok, M missing, K detached" for worktree $1 ("" when no entries)
  local m p ok=0 missing=0 detached=0
  REPLY=""
  while IFS=$'\t' read -r m p; do
    _carryStatus "$1" "$p" "$m"
    case $REPLY in
    missing) missing=$((missing + 1)) ;;
    detached) detached=$((detached + 1)) ;;
    *) ok=$((ok + 1)) ;;
    esac
  done < <(_carryEntries)
  ((ok + missing + detached)) || return 0
  REPLY="$ok ok"
  ((missing)) && REPLY+=", ${C_RED}$missing missing${C_RESET}"
  ((detached)) && REPLY+=", ${C_YELLOW}$detached detached${C_RESET}"
  return 0
}
#}}}: _carryCounts

_carryDivergent() { #{{{
  # Prints configured paths whose real file in worktree $1 differs from the store
  local m p f
  while IFS=$'\t' read -r m p; do
    f="$1/$p"
    [[ -f $f && ! -L $f ]] || continue
    cmp -s "$f" "$(_carryStore)/$p" || echo "$p"
  done < <(_carryEntries)
}
#}}}: _carryDivergent

_ignoredFiles() { #{{{
  # Ignored regular files of worktree $1, relative; ignored directories are
  # dropped whole and .DS_Store is noise.
  local e
  while IFS= read -r e; do
    [[ $e == */ || ${e##*/} == .DS_Store ]] && continue
    [[ -f "$1/$e" || -L "$1/$e" ]] && echo "$e"
  done < <(git -C "$1" ls-files --others --ignored --exclude-standard --directory)
}
#}}}: _ignoredFiles

_worktrees() { #{{{
  # Prints "path<TAB>branch" for every non-bare worktree
  local path="" line
  while IFS= read -r line; do
    case $line in
    "worktree "*) path="${line#worktree }" ;;
    "branch refs/heads/"*) printf '%s\t%s\n' "$path" "${line#branch refs/heads/}" ;;
    esac
  done < <(git worktree list --porcelain)
}
#}}}: _worktrees

_scanIgnored() { #{{{
  # Ignored files across all worktrees. Prints per path:
  #   path<US>branches (comma separated)<US>differs (0|1)<US>first source file
  local wt br p h
  local -A where hash differs first
  local -a order=()
  while IFS=$'\t' read -r wt br; do
    while IFS= read -r p; do
      [[ -n ${where[$p]-} ]] || { order+=("$p"); first[$p]="$wt/$p"; }
      where[$p]+="${where[$p]:+,}$br"
      [[ -L "$wt/$p" ]] && continue
      h="$(shasum "$wt/$p" 2>/dev/null | cut -c1-40)"
      if [[ -z ${hash[$p]-} ]]; then hash[$p]="$h"
      elif [[ ${hash[$p]} != "$h" ]]; then differs[$p]=1; fi
    done < <(_ignoredFiles "$wt")
  done < <(_worktrees)
  for p in "${order[@]+"${order[@]}"}"; do
    printf '%s\x1f%s\x1f%s\x1f%s\n' "$p" "${where[$p]}" "${differs[$p]-0}" "${first[$p]}"
  done
}
#}}}: _scanIgnored

_carrySources() { #{{{
  # Prints "path<TAB>branch" of every worktree holding $1 as a real file or link
  local wt br
  while IFS=$'\t' read -r wt br; do
    [[ -e "$wt/$1" || -L "$wt/$1" ]] && printf '%s\t%s\n' "$wt" "$br"
  done < <(_worktrees)
  return 0
}
#}}}: _carrySources

_carrySource() { #{{{
  # Worktree to seed the store from for $1, preferring $2 (here); asks when copies differ.
  local here="$2" wt br n
  local -a wts=() brs=()
  [[ -f "$here/$1" && ! -L "$here/$1" ]] && { echo "$here"; return 0; }
  while IFS=$'\t' read -r wt br; do
    [[ -f "$wt/$1" && ! -L "$wt/$1" ]] || continue
    wts+=("$wt"); brs+=("$br")
  done < <(_carrySources "$1")
  n=${#wts[@]}
  ((n)) || return 1
  ((n == 1)) && { echo "${wts[0]}"; return 0; }
  local firstWt="${wts[0]}" same=1 i
  for ((i = 1; i < n; i++)); do cmp -s "$firstWt/$1" "${wts[i]}/$1" || { same=0; break; }; done
  ((same)) && { echo "$firstWt"; return 0; }
  # Copies differ: pick the source branch
  local pick
  pick="$(for ((i = 0; i < n; i++)); do printf '%s\t%s\n' "${wts[i]}" "${brs[i]}"; done |
    fzf --exact --delimiter=$'\t' --with-nth=2 --layout=reverse-list \
      --header "'$1' differs between worktrees: pick the source" \
      --preview "$(_previewFileCmd '{1}'"/$1")" --preview-window="right:60%,wrap" |
    cut -f1)" || true
  [[ -n $pick ]] || _die "No source selected for '$1'."
  echo "$pick"
}
#}}}: _carrySource

_previewFileCmd() { #{{{
  # Shell snippet that prints file $1 with syntax colors when bat is available
  if command -v bat >/dev/null; then
    echo "bat --color=always --style=plain --line-range=:300 $1 2>/dev/null"
  else
    echo "head -n 300 $1 2>/dev/null"
  fi
}
#}}}: _previewFileCmd

_humanSize() { #{{{
  local b
  b="$(stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0)"
  if ((b < 1024)); then REPLY="${b}B"
  elif ((b < 1048576)); then REPLY="$((b / 1024))K"
  else REPLY="$((b / 1048576))M"; fi
}
#}}}: _humanSize

_carryTable() { #{{{
  # One line per ignored (any worktree) or configured file, relative to worktree $1:
  #   path<TAB>display<TAB>preview file
  # display = "status  size  from  path"; status is for $1 ("here").
  local here="$1" hereBr
  local -A mode seen
  local -a rows=()
  local m p b br diff src st size padSt from padFrom
  hereBr="$(git -C "$here" branch --show-current 2>/dev/null || true)"
  while IFS=$'\t' read -r m p; do mode[$p]="$m"; done < <(_carryEntries)
  while IFS=$'\x1f' read -r p br diff src; do
    rows+=("$p"$'\x1f'"$br"$'\x1f'"$diff"$'\x1f'"$src"); seen[$p]=1
  done < <(_scanIgnored)
  for p in "${!mode[@]}"; do
    [[ -n ${seen[$p]-} ]] || rows+=("$p"$'\x1f'""$'\x1f'"0"$'\x1f'"")
    seen[$p]=1
  done
  # Store files nobody carries any more (left behind by forget)
  local store
  store="$(_carryStore)"
  if [[ -d $store ]]; then
    while IFS= read -r p; do
      p="${p#"$store"/}"
      [[ -n ${seen[$p]-} ]] || rows+=("$p"$'\x1f'""$'\x1f'"0"$'\x1f'"$store/$p")
    done < <(find "$store" -type f ! -name .DS_Store)
  fi
  ((${#rows[@]})) || return 0

  while IFS=$'\x1f' read -r p br diff src; do
    _carryStatus "$here" "$p" "${mode[$p]-}"; st="$REPLY"
    [[ -z ${mode[$p]-} && -e "$store/$p" ]] && st="orphan"
    if [[ -e "$here/$p" || -L "$here/$p" ]]; then
      _humanSize "$here/$p"; size="$REPLY"; src="$here/$p"
    elif [[ -n $src ]]; then
      _humanSize "$src"; size="$REPLY"
    else
      size=""
    fi
    from=""
    local -a brs=()
    IFS=',' read -r -a brs <<<"$br"
    for b in "${brs[@]+"${brs[@]}"}"; do
      [[ $b == "$hereBr" ]] && b="here"
      from+="${from:+,}$b"
    done
    [[ -z $from ]] && from="(store only)"
    ((diff)) && from+=" differs"
    _pad "$st" 9; padSt="$REPLY"
    _pad "$from" 28; padFrom="$REPLY"
    case $st in
    link) padSt="${C_GREEN}${padSt}${C_RESET}" ;;
    copy) padSt="${C_BLUE}${padSt}${C_RESET}" ;;
    detached | orphan) padSt="${C_YELLOW}${padSt}${C_RESET}" ;;
    missing) padSt="${C_RED}${padSt}${C_RESET}" ;;
    *) padSt="${C_DIM}${padSt}${C_RESET}" ;;
    esac
    padFrom="${padFrom//differs/${C_RED}differs${C_RESET}}"
    printf '%s\t%s  %s%5s%s  %s%s%s  %s\t%s\n' \
      "$p" "$padSt" "$C_DIM" "$size" "$C_RESET" "$C_MAGENTA" "$padFrom" "$C_RESET" "$p" "$src"
  done < <(printf '%s\n' "${rows[@]}" | sort -t $'\x1f' -k1,1 -u)
}
#}}}: _carryTable

_carryPick() { #{{{
  # Multi-select picker over _carryTable of worktree $1; $2 = header hint.
  # The query starts as the current subdirectory so nearby files come first.
  # Prints the action chosen by key (link|copy|detach|forget, empty for Enter)
  # on the first line, then the chosen paths.
  local query="" out key
  [[ $PWD == "$1"/* ]] && query="${PWD#"$1"/}/"
  out="$(_carryTable "$1" |
    _fzf --multi --query "$query" --header "$(_header "$2")" \
      --expect=ctrl-s,ctrl-o,ctrl-x,ctrl-f \
      --preview "$(_previewFileCmd '{3}')" --preview-window="right:50%,wrap,<120(down:50%)")" || true
  [[ -n $out ]] || return 0
  key="${out%%$'\n'*}"
  case $key in
  ctrl-s) echo "link" ;;
  ctrl-o) echo "copy" ;;
  ctrl-x) echo "detach" ;;
  ctrl-f) echo "forget" ;;
  *) echo "" ;;
  esac
  printf '%s\n' "$out" | sed '1d' | cut -f1
}
#}}}: _carryPick

_carryKeysHint() { #{{{
  # Key legend for the carry picker header, limited to the allowed actions $1
  local hint=""
  [[ $1 == *l* ]] && hint+="  ctrl-s link"
  [[ $1 == *c* ]] && hint+="  ctrl-o copy"
  [[ $1 == *d* ]] && hint+="  ctrl-x detach"
  [[ $1 == *f* ]] && hint+="  ctrl-f forget"
  echo "TAB multi  ·${hint}  ·  Enter asks"
}
#}}}: _carryKeysHint

_carryAction() { #{{{
  # $1 = allowed letters (subset of lcdf), $2 = file count. Sets REPLY.
  local a menu=""
  [[ $1 == *l* ]] && menu+="  [l]ink (shared)"
  [[ $1 == *c* ]] && menu+="  [c]opy (per branch)"
  [[ $1 == *d* ]] && menu+="  [d]etach (this worktree)"
  [[ $1 == *f* ]] && menu+="  [f]orget"
  read -n 1 -r -p ">> Action for $2 file(s):$menu: " a
  echo >&2
  [[ -n $a && $1 == *"$a"* ]] || _die "Aborted."
  case $a in
  l) REPLY="link" ;;
  c) REPLY="copy" ;;
  d) REPLY="detach" ;;
  f) REPLY="forget" ;;
  esac
}
#}}}: _carryAction

_baseWorktree() { #{{{
  # Worktree to take local files from: the base branch's, else the current, else the default's
  local wt=""
  [[ -n ${1-} ]] && wt="$(_worktreePath "$(_localName "$1")")"
  [[ -z $wt && -n $currentBranch ]] && wt="$(_worktreePath "$currentBranch")"
  [[ -z $wt && -n $defaultBranch ]] && wt="$(_worktreePath "$defaultBranch")"
  echo "$wt"
}
#}}}: _baseWorktree

_carryFirstTime() { #{{{
  # $1 = new worktree, $2 = worktree to pick files from
  local -a sel=()
  local mode p
  # Nothing ignored anywhere yet: stay quiet and ask again when there is
  [[ -n "$(_carryTable "$1")" ]] || return 0
  mapfile -t sel < <(_carryPick "$1" "pick local files to carry into every worktree  ·  $(_carryKeysHint lc)  ·  Esc = none")
  mode="${sel[0]-}"
  sel=("${sel[@]:1}")
  if ((${#sel[@]} == 0)); then
    _carryMarkNone
    _msg "carry: nothing chosen. Run 'sw carry' inside a worktree to change that."
    return 0
  fi
  case $mode in
  link | copy) ;;
  *) _carryAction lc "${#sel[@]}"; mode="$REPLY" ;;
  esac
  for p in "${sel[@]}"; do
    _carrySet "$mode" "$p"
    _carrySeedFrom "$p" "$mode" "${2:-$1}"
  done
  _carryApply "$1"
}
#}}}: _carryFirstTime

_carrySeedFrom() { #{{{
  # Seed the store with $1 (mode $2) from the best source worktree, preferring $3.
  # For link mode every worktree holding an identical copy becomes a link.
  local src wt br
  if [[ ! -e "$(_carryStore)/$1" ]]; then
    src="$(_carrySource "$1" "$3")" || { _msg "carry: '$1' found nowhere, skipped."; return 0; }
    _carrySeedStore "$src" "$1" "$2"
  fi
  if [[ $2 == link ]]; then
    while IFS=$'\t' read -r wt br; do
      [[ -L "$wt/$1" ]] || { _carryLinkInto "$wt" "$1" || true; }
    done < <(_carrySources "$1")
  fi
}
#}}}: _carrySeedFrom

_afterWorktreeCreated() { #{{{
  # $1 = new worktree, $2 = base worktree (may be empty)
  [[ -n $barePath ]] || return 0
  if _carryHasEntries; then
    _carryApply "$1"
  elif ! _carryAsked; then
    _carryFirstTime "$1" "$2"
  fi
}
#}}}: _afterWorktreeCreated

_carryPaths() { #{{{
  # Paths to act on: $2 when given, else a picker over worktree $1 ($3 = hint).
  # Prints one path per line.
  if [[ -n ${2-} ]]; then
    echo "$2"
  else
    _carryPick "$1" "$3" | sed '1d'
  fi
}
#}}}: _carryPaths

_carryDiff() { #{{{
  # Diff the store copy of $2 (or every configured path) against each
  # worktree holding a differing real file.
  local wt br p m store f shown=0
  local -a paths=()
  if [[ -n ${2-} ]]; then
    paths=("$2")
  else
    while IFS=$'\t' read -r m p; do paths+=("$p"); done < <(_carryEntries)
  fi
  ((${#paths[@]})) || _die "carry: nothing configured."
  for p in "${paths[@]}"; do
    store="$(_carryStore)/$p"
    [[ -e $store ]] || { _msg "carry: '$p' is not in the store."; continue; }
    while IFS=$'\t' read -r wt br; do
      f="$wt/$p"
      [[ -f $f && ! -L $f ]] || continue
      cmp -s "$store" "$f" && continue
      printf '%s%s%s  store → %s\n' "$C_BOLD" "$p" "$C_RESET" "$br"
      git diff --no-index --color=always -- "$store" "$f" || true
      shown=$((shown + 1))
    done < <(_carrySources "$p")
  done
  ((shown)) || _msg "carry: no local copy differs from the store."
}
#}}}: _carryDiff

_carryReset() { #{{{
  # Replace the local copy in worktree $1 with the store version (link or copy per config)
  local wt="$1" p m
  local -a paths=() todo=()
  local -A mode
  while IFS=$'\t' read -r m p; do mode[$p]="$m"; done < <(_carryEntries)
  mapfile -t paths < <(_carryPaths "$wt" "${2-}" "pick files to reset from the store")
  for p in "${paths[@]+"${paths[@]}"}"; do
    [[ -n ${mode[$p]-} ]] || { _msg "carry: '$p' is not carried, skipped."; continue; }
    [[ -e "$(_carryStore)/$p" ]] || { _msg "carry: '$p' is not in the store, skipped."; continue; }
    todo+=("$p")
  done
  ((${#todo[@]})) || _die "Nothing to reset."
  _prompt "Discard the local version of ${#todo[@]} file(s) in $(basename "$wt") and take the store's?"
  for p in "${todo[@]}"; do
    rm -f "$wt/$p"
    if [[ ${mode[$p]} == link ]]; then _carryLinkInto "$wt" "$p" || true
    else _carryCopyInto "$wt" "$p" || true; fi
  done
  _msg "carry: reset ${#todo[@]} file(s) from the store."
}
#}}}: _carryReset

_carryEdit() { #{{{
  # Open the store copy of $2 (or a picked file) in $EDITOR
  local p store
  p="$(_carryPaths "$1" "${2-}" "pick the file to edit in the store" | head -n1)"
  [[ -n $p ]] || _die "No file selected!"
  store="$(_carryStore)/$p"
  [[ -e $store ]] || _die "carry: '$p' is not in the store."
  # stdout is captured by the .zshrc wrapper, so hand the editor the terminal
  "${EDITOR:-vi}" "$store" </dev/tty >/dev/tty
  _msg "carry: edited the store copy of '$p'. Links see it; copies need 'sw carry reset $p'."
}
#}}}: _carryEdit

_carryPruneStore() { #{{{
  # Offer to delete the store copies of $@ (used after forget)
  local p
  local -a gone=()
  for p in "$@"; do [[ -e "$(_carryStore)/$p" ]] && gone+=("$p"); done
  ((${#gone[@]})) || return 0
  _ask "Also delete ${#gone[@]} file(s) from the store ($(_carryStore))?" || return 0
  for p in "${gone[@]}"; do rm -f "$(_carryStore)/$p"; done
  find "$(_carryStore)" -type d -empty -delete 2>/dev/null || true
}
#}}}: _carryPruneStore

_carryManage() { #{{{
  # sw carry [ls|apply|diff|reset|edit] [path]
  local wt sub="$1" arg="${2-}" mode p
  local -a sel=()
  [[ -n $barePath ]] || _die "carry needs a bare+worktree repo."
  wt="$(_worktreePath "$currentBranch")"
  [[ -n $wt ]] || _die "Run 'sw carry' from inside a worktree."

  case $sub in
  ls) _carryTable "$wt" | cut -f2 | _plain; return 0 ;;
  apply)
    _carryHasEntries || _die "carry: nothing configured. Run 'sw carry' to pick files."
    _carryApply "$wt"
    return 0
    ;;
  diff) _carryDiff "$wt" "$arg" | _plain; return 0 ;;
  reset) _carryReset "$wt" "$arg"; return 0 ;;
  edit) _carryEdit "$wt" "$arg"; return 0 ;;
  '') ;;
  *) _die "sw carry: unknown subcommand '$sub' (ls, apply, diff, reset, edit)" ;;
  esac

  mapfile -t sel < <(_carryPick "$wt" "$(_carryKeysHint lcdf)")
  mode="${sel[0]-}"
  sel=("${sel[@]:1}")
  ((${#sel[@]})) || _die "No files selected!"
  [[ -n $mode ]] || { _carryAction lcdf "${#sel[@]}"; mode="$REPLY"; }

  for p in "${sel[@]}"; do
    case $mode in
    link)
      _carrySet link "$p"
      _carrySeedFrom "$p" link "$wt"
      _carryLinkInto "$wt" "$p" || true
      ;;
    copy)
      _carrySet copy "$p"
      _carrySeedFrom "$p" copy "$wt"
      _carryCopyInto "$wt" "$p" || true
      ;;
    detach) _carryDetach "$wt" "$p" || true ;;
    forget) _carryForget "$p" ;;
    esac
  done
  _msg "carry: $mode applied to ${#sel[@]} file(s)."
  [[ $mode == forget ]] && _carryPruneStore "${sel[@]}"
  return 0
}
#}}}: _carryManage

# ---------------------------------------------------------------- main

if ((showHelp)); then
  _usage
  exit 0
fi

barePath="$(_worktreePath "")"
repoRoot="${barePath%/*}"
currentBranch="$(git branch --show-current 2>/dev/null || true)"
remote="$(_cfg remote origin)"
defaultBranch="$(_defaultBranch)"
readonly barePath repoRoot currentBranch remote defaultBranch

if ((previewMode)); then
  _preview "$branch"
  exit 0
fi

if ((tableMode)); then
  # Used by the picker's reload keys; SW_EXCLUDE hides the current branch
  _branchTable "$branch" | awk -F'\t' -v cur="${SW_EXCLUDE-}" '$1 != cur'
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

if ((carryMode)); then
  sub="$branch"
  ((gitList)) && sub="ls"
  _carryManage "$sub" "$base"
  exit 0
fi

if ((statusMode)); then
  _status | _plain
  exit 0
fi

if ((gitList)); then
  _branchTable | cut -f2 | _plain
  exit 0
fi

if ((goBack)); then
  prev="$(_previousBranch)" || _die "No previous branch to go back to."
  _switch "$prev"
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
reloadCmd="SW_EXCLUDE=$(printf '%q' "$currentBranch") $(printf '%q' "$0") --table"
out="$(_branchTable | awk -F'\t' -v cur="$currentBranch" '$1 != cur' |
  _fzf --multi --print-query --expect=ctrl-x,ctrl-o \
    --bind "ctrl-r:reload($reloadCmd)" \
    --bind "ctrl-f:reload(git fetch --all --prune >/dev/null 2>&1; $reloadCmd)" \
    --header "$(_header "Enter switch  ·  ctrl-x delete  ·  ctrl-o create from  ·  ctrl-f fetch  ·  new name: create from $defaultBranch")")" || rc=$?

# Output: query, key pressed (empty for Enter), then the selected lines
mapfile -t lines <<<"$out"
query="${lines[0]-}"
key="${lines[1]-}"
mapfile -t picked < <(printf '%s\n' "${lines[@]:2}" | cut -f1 | sed '/^$/d')

case $rc in
0)
  ((${#picked[@]})) || _die "No branch selected!"
  case $key in
  ctrl-x) _delete "${picked[@]}" ;;
  ctrl-o)
    read -r -p ">> New branch (from ${picked[0]}): " new
    [[ -n $new ]] || _die "Branch name cannot be empty!"
    _hasLocal "$new" && _die "Branch '$new' already exists."
    _createBranch "$new" "$(_localName "${picked[0]}")"
    ;;
  *) _switch "${picked[0]}" ;;
  esac
  ;;
1)
  # fzf: no match for the query
  [[ -n $query && -z $key ]] || _die "No branch selected!"
  _offerCreate "$query"
  ;;
*) _die "No branch selected!" ;;
esac
