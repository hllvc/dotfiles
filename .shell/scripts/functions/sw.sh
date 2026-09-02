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
#   carry      manage gitignored local files carried into worktrees:
#              `sw carry` picker (link/copy/detach/forget), `sw carry ls`, `sw carry apply`
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

fetchAll=0 deleteBranch=0 gitList=0 createBranch=0 showHelp=0 previewMode=0 carryMode=0
branch="" base=""

for arg; do
  case $arg in
  'a' | '-a') fetchAll=1 ;;
  'd' | '-d') deleteBranch=1 ;;
  'ls' | 'l' | '-l') gitList=1 ;;
  [cn] | -[cn]) createBranch=1 ;;
  '-h' | '--help') showHelp=1 ;;
  '--preview') previewMode=1 ;;
  'carry') carryMode=1 ;;
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
    _carryCounts "$path"
    [[ -n $REPLY ]] && printf '%scarry%s %s\n' "$C_BOLD" "$C_RESET" "$REPLY"
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
  _afterWorktreeCreated "$dir" "$(_baseWorktree "$from")"
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
  local t p path dirty summary="" leaving=0 rc=0

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
    path="$(_addWorktree "$name")"
    _afterWorktreeCreated "$path" "$(_baseWorktree "")"
    echo "$path"
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
  # link | copy | detached | missing | - (present, not carried)
  local f="$1/$2" mode="$3"
  if [[ -L $f ]]; then
    REPLY="link"
  elif [[ -e $f ]]; then
    case $mode in
    link) REPLY="detached" ;;
    copy) REPLY="copy" ;;
    *) REPLY="-" ;;
    esac
  else
    REPLY="missing"
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
  # Ignored regular files of worktree $1, relative; ignored directories are dropped whole
  local e
  while IFS= read -r e; do
    [[ $e == */ ]] && continue
    [[ -f "$1/$e" || -L "$1/$e" ]] && echo "$e"
  done < <(git -C "$1" ls-files --others --ignored --exclude-standard --directory)
}
#}}}: _ignoredFiles

_humanSize() { #{{{
  local b
  b="$(stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0)"
  if ((b < 1024)); then REPLY="${b}B"
  elif ((b < 1048576)); then REPLY="$((b / 1024))K"
  else REPLY="$((b / 1048576))M"; fi
}
#}}}: _humanSize

_carryTable() { #{{{
  # One line per ignored or configured file of worktree $1:  path<TAB>display
  local -A mode seen
  local -a paths=()
  local m p st size padSt
  while IFS=$'\t' read -r m p; do mode[$p]="$m"; done < <(_carryEntries)
  while IFS= read -r p; do paths+=("$p"); seen[$p]=1; done < <(_ignoredFiles "$1")
  for p in "${!mode[@]}"; do [[ -n ${seen[$p]-} ]] || paths+=("$p"); done
  ((${#paths[@]})) || return 0

  while IFS= read -r p; do
    _carryStatus "$1" "$p" "${mode[$p]-}"; st="$REPLY"
    if [[ -e "$1/$p" || -L "$1/$p" ]]; then _humanSize "$1/$p"; size="$REPLY"; else size=""; fi
    _pad "$st" 8; padSt="$REPLY"
    case $st in
    link) padSt="${C_GREEN}${padSt}${C_RESET}" ;;
    copy) padSt="${C_BLUE}${padSt}${C_RESET}" ;;
    detached) padSt="${C_YELLOW}${padSt}${C_RESET}" ;;
    missing) padSt="${C_RED}${padSt}${C_RESET}" ;;
    *) padSt="${C_DIM}${padSt}${C_RESET}" ;;
    esac
    printf '%s\t%s  %s%5s%s  %s\n' "$p" "$padSt" "$C_DIM" "$size" "$C_RESET" "$p"
  done < <(printf '%s\n' "${paths[@]}" | sort -u)
}
#}}}: _carryTable

_carryPick() { #{{{
  # Multi-select picker over _carryTable of worktree $1; $2 = header hint.
  # Prints the chosen paths, one per line.
  _carryTable "$1" |
    _fzf --multi --header "$(_header "$2")" \
      --preview "ls -la '$1'/{1} 2>/dev/null; echo; printf '%s lines\n' \"\$(wc -l < '$1'/{1} 2>/dev/null)\"" |
    cut -f1 || true
}
#}}}: _carryPick

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
  [[ -d ${2-} && $2 != "$1" ]] || return 0
  mapfile -t sel < <(_carryPick "$2" "pick local files to carry into every worktree (TAB, Enter; Esc = none)")
  if ((${#sel[@]} == 0)); then
    _carryMarkNone
    _msg "carry: nothing chosen. Run 'sw carry' inside a worktree to change that."
    return 0
  fi
  _carryAction lc "${#sel[@]}"; mode="$REPLY"
  for p in "${sel[@]}"; do
    _carrySet "$mode" "$p"
    _carrySeedStore "$2" "$p" "$mode"
  done
  _carryApply "$1"
}
#}}}: _carryFirstTime

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

_carryManage() { #{{{
  # sw carry [ls|apply]
  local wt sub="$1" mode p defaultWt
  local -a sel=()
  [[ -n $barePath ]] || _die "carry needs a bare+worktree repo."
  wt="$(_worktreePath "$currentBranch")"
  [[ -n $wt ]] || _die "Run 'sw carry' from inside a worktree."

  case $sub in
  ls)
    if [[ -t 1 ]]; then _carryTable "$wt" | cut -f2
    else _carryTable "$wt" | cut -f2 | sed $'s/\e\\[[0-9;]*m//g'; fi
    return 0
    ;;
  apply)
    _carryHasEntries || _die "carry: nothing configured. Run 'sw carry' to pick files."
    _carryApply "$wt"
    return 0
    ;;
  '') ;;
  *) _die "sw carry: unknown subcommand '$sub' (ls, apply)" ;;
  esac

  mapfile -t sel < <(_carryPick "$wt" "TAB: multi  ·  then link / copy / detach / forget")
  ((${#sel[@]})) || _die "No files selected!"
  _carryAction lcdf "${#sel[@]}"; mode="$REPLY"
  defaultWt="$(_worktreePath "$defaultBranch")"

  for p in "${sel[@]}"; do
    case $mode in
    link)
      _carrySet link "$p"
      _carrySeedStore "$wt" "$p" link
      [[ -n $defaultWt && $defaultWt != "$wt" && -e "$defaultWt/$p" ]] && { _carryLinkInto "$defaultWt" "$p" || true; }
      ;;
    copy)
      _carrySet copy "$p"
      _carrySeedStore "$wt" "$p" copy
      _carryCopyInto "$wt" "$p" || true
      ;;
    detach) _carryDetach "$wt" "$p" || true ;;
    forget) _carryForget "$p" ;;
    esac
  done
  _msg "carry: $mode applied to ${#sel[@]} file(s)."
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

if ((carryMode)); then
  sub="$branch"
  ((gitList)) && sub="ls"
  _carryManage "$sub"
  exit 0
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
