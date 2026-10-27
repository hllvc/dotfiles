#!/usr/bin/env bash
#
# sw — fzf branch switcher with bare+worktree support.
#
# Usage: sw [-a] [-l] [-L|-r] [-c|-n] [-d] [-h] [branch] [base]
#   (none)     pick a branch and switch to it (worktree-aware)
#   branch     skip the picker; an unknown name offers to create it
#   -          switch back to the previous branch
#   -a         fetch --all --prune first
#   -l, ls     list branches and exit
#   -L         local branches only (hide remote-only refs)
#   -r         every remote-only branch (default: yours or active in the
#              last sw.remoteAge days)
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
#              ctrl-r fetch + reload  ctrl-a all remotes
#              alt-m merged only  alt-g gone only  alt-n new only  alt-0 all
#              (the filter shows in the prompt and survives ctrl-r)
#              ctrl-/ key and legend cheat sheet in the preview pane
#   carry:     ctrl-s link  ctrl-o copy  ctrl-t detach  ctrl-x forget
#
# Config (git config, e.g. in .bare/config):
#   sw.remote      remote to track (default origin)
#   sw.rebase      false = never rebase after -c
#   sw.postCreate  shell command run inside every new worktree
#   sw.remoteAge   days a remote-only branch counts as active (default 14)
#
# Picker line: [*·]name  where  status  age  subject
#   *        current branch; · visited recently (listed first, latest visit on top)
#   name     colored by state: dim = merged (changes already on
#            <remote>/<default>: ff, rebase or squash), cyan = new (no commits
#            of its own yet: at the default tip, or WIP), bold = anything else
#   where    worktree | local | remote (remote only)
#   status   against its own <remote>/<name>: ⇡ahead ⇣behind | unpushed | gone
#            (blank = in sync), then the worktree's changes like the prompt:
#            ~conflicted +staged !modified ?untracked
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
tableMode=0 statusMode=0 goBack=0 localOnly=0 allRemotes=0 noRebase=0
branch="" base="" onlyState="" keysMode="" keysToggle=""

for arg; do
  case $arg in
  'a' | '-a') fetchAll=1 ;;
  'd' | '-d') deleteBranch=1 ;;
  'ls' | 'l' | '-l') gitList=1 ;;
  '-L') localOnly=1 ;;
  '-r') allRemotes=1 ;;
  [cn] | -[cn]) createBranch=1 ;;
  '--no-rebase') noRebase=1 ;;
  '-h' | '--help') showHelp=1 ;;
  '--preview') previewMode=1 ;;
  --keys=*) keysMode="${arg#--keys=}" ;;
  --keys-toggle=*) keysToggle="${arg#--keys-toggle=}" ;;
  '--table') tableMode=1 ;;
  --only=*)
    # Comes from the picker prompt: anything but a known filter means none
    case ${arg#--only=} in
    merged | gone | new) onlyState="${arg#--only=}" ;;
    esac
    ;;
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
C_CYAN=$'\e[36m'


_usage() { #{{{
  sed -n '/^# Usage/,/^# Prints a directory/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'
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

_cacheDir() { #{{{
  echo "${barePath:-$(git rev-parse --git-common-dir 2>/dev/null)}"
}
#}}}: _cacheDir

_stateInit() { #{{{
  # Load the merge-state cache for the current base. Entries are keyed by
  # branch tip and only valid for one base sha, so a moved base starts over.
  local tip base own merged
  declare -gA stateCache=()
  stateFile="$(_cacheDir)/sw.state" patchFile="" stateChanged=0
  baseSha="$(git rev-parse -q --verify "$baseRef^{commit}" 2>/dev/null || true)"
  [[ -f $stateFile && -n $baseSha ]] || return 0
  while read -r tip base own merged; do
    [[ $base == "$baseSha" ]] && stateCache[$tip]="$own $merged"
  done <"$stateFile"
}
#}}}: _stateInit

_stateSave() { #{{{
  local tip
  ((stateChanged)) && [[ -n $baseSha && -d ${stateFile%/*} ]] || return 0
  for tip in "${!stateCache[@]}"; do
    printf '%s %s %s\n' "$tip" "$baseSha" "${stateCache[$tip]}"
  done >"$stateFile.tmp" && mv "$stateFile.tmp" "$stateFile"
}
#}}}: _stateSave

_patchIds() { #{{{
  # Sets patchFile to a sorted list of the patch-ids of every non-merge commit
  # on the base (first line: the base sha it was built for). Rebuilt only
  # when the base moves.
  [[ -n $patchFile ]] && return 0
  patchFile="$(_cacheDir)/sw.patchids"
  [[ -f $patchFile && "$(head -n1 "$patchFile")" == "$baseSha" ]] && return 0
  {
    echo "$baseSha"
    git log -p --no-merges --format='commit %H' "$baseRef" | git patch-id --stable | cut -d' ' -f1 | sort -u
  } >"$patchFile.tmp" && mv "$patchFile.tmp" "$patchFile"
}
#}}}: _patchIds

_mergeInfo() { #{{{
  # $1 = ref, $2 = its sha. Sets OWN (commits not on the base) and MERGED
  # to how its changes reached the base: ff (no own commits), rebase (every
  # commit has an equal patch there), squash (the whole diff does) or "".
  local ref="$1" tip="$2" mb pid
  OWN=0 MERGED=""
  [[ -n $baseSha ]] || return 0
  if [[ -n ${stateCache[$tip]-} ]]; then
    read -r OWN MERGED <<<"${stateCache[$tip]}"
    [[ $MERGED == - ]] && MERGED=""
    return 0
  fi
  OWN="$(git rev-list --count "$baseSha..$tip" 2>/dev/null || echo 0)"
  if ((OWN == 0)); then
    MERGED="ff"
  else
    _patchIds
    # Patches missing from the base (comm -23 prints lines only in the first list)
    if [[ -z "$(git log -p --no-merges --format='commit %H' "$baseSha..$tip" | git patch-id --stable |
      cut -d' ' -f1 | sort -u | comm -23 - <(sed 1d "$patchFile"))" ]]; then
      MERGED="rebase"
    elif mb="$(git merge-base "$baseSha" "$tip" 2>/dev/null)"; then
      pid="$(git diff "$mb" "$tip" | git patch-id --stable | cut -d' ' -f1)"
      [[ -n $pid ]] && sed 1d "$patchFile" | grep -qxF "$pid" && MERGED="squash"
    fi
  fi
  stateCache[$tip]="$OWN ${MERGED:--}"
  stateChanged=1
}
#}}}: _mergeInfo

_state() { #{{{
  # $1 = ref, $2 = its sha, $3 = dirty count (0 without a worktree).
  # Sets OWN and MERGED (see _mergeInfo) and REPLY to new | merged | "".
  _mergeInfo "$1" "$2"
  REPLY=""
  # The default branch is the base itself: no merge state to speak of
  [[ $1 == "$defaultBranch" || $1 == "$baseRef" ]] && return 0
  # No commits of its own is only "merged" for a branch that moved on from the
  # base it started at; one sitting at the base tip or holding WIP is new.
  if ((OWN == 0)) && [[ $2 == "$baseSha" || ${3:-0} -gt 0 ]]; then
    REPLY="new"
  elif [[ -n $MERGED ]]; then
    REPLY="merged"
  fi
}
#}}}: _state

_sync() { #{{{
  # Where a local branch stands against its own remote branch.
  # $1 = name, $2 = sha, $3 = upstream ref, $4 = upstream:track text,
  # $5 = <remote>/<name> sha (empty when absent), $6 = state from _state
  # (which also set the OWN this reads). Sets REPLY to "⇡N ⇣M" | unpushed |
  # gone, or "" when in sync or there is nothing to lose.
  local name="$1" sha="$2" upstream="$3" text="$4" remoteSha="$5" state="${6-}"
  local ahead="" behind="" counts
  REPLY=""
  # Branching off origin/main makes git track origin/main; that says nothing
  # about whether this branch is pushed.
  [[ $upstream == "$remote/$defaultBranch" && $name != "$defaultBranch" ]] && upstream="" text=""
  if [[ -n $upstream ]]; then
    if [[ $text == gone ]]; then REPLY="gone"; return 0; fi
    [[ $text =~ ahead\ ([0-9]+) ]] && ahead="${BASH_REMATCH[1]}"
    [[ $text =~ behind\ ([0-9]+) ]] && behind="${BASH_REMATCH[1]}"
  elif [[ -n $remoteSha ]]; then
    if [[ $remoteSha != "$sha" ]]; then
      counts="$(git rev-list --left-right --count "$sha...$remoteSha" 2>/dev/null || true)"
      ahead="${counts%%[[:space:]]*}" behind="${counts##*[[:space:]]}"
      [[ $ahead == 0 ]] && ahead=""
      [[ $behind == 0 ]] && behind=""
    fi
  else
    # Nothing to compare with: only worth a flag when work would be lost
    ((OWN > 0)) && [[ $state != merged ]] && REPLY="unpushed"
    return 0
  fi
  REPLY="${ahead:+⇡$ahead}${ahead:+${behind:+ }}${behind:+⇣$behind}"
}
#}}}: _sync

_syncColor() { #{{{
  # Sets REPLY to the _sync text $1 colored for display
  case $1 in
  gone | unpushed) REPLY="${C_RED}$1${C_RESET}" ;;
  *) REPLY="${C_GREEN}$1${C_RESET}" ;;
  esac
  [[ -n $1 ]] || REPLY=""
}
#}}}: _syncColor

_statusCounts() { #{{{
  # Reads `git status --porcelain` and prints "total staged modified untracked conflicted"
  awk '{
    t++; x = substr($0, 1, 1); y = substr($0, 2, 1)
    if (x == "?") { u++; next }
    if (x y ~ /^(DD|AU|UD|UA|DU|AA|UU)$/) { c++; next }
    if (x != " ") s++
    if (y != " ") m++
  } END { printf "%d %d %d %d %d\n", t, s, m, u, c }'
}
#}}}: _statusCounts

_changes() { #{{{
  # $1 = "staged modified untracked conflicted" counts. Sets REPLY to the
  # powerlevel10k-style "~c +s !m ?u" (colored) and PLAIN to the same uncolored.
  local s m u c
  read -r s m u c <<<"$1"
  REPLY="" PLAIN=""
  ((${c:-0})) && { REPLY+=" ${C_RED}~$c${C_RESET}"; PLAIN+=" ~$c"; }
  ((${s:-0})) && { REPLY+=" ${C_YELLOW}+$s${C_RESET}"; PLAIN+=" +$s"; }
  ((${m:-0})) && { REPLY+=" ${C_YELLOW}!$m${C_RESET}"; PLAIN+=" !$m"; }
  ((${u:-0})) && { REPLY+=" ${C_BLUE}?$u${C_RESET}"; PLAIN+=" ?$u"; }
  REPLY="${REPLY# }" PLAIN="${PLAIN# }"
}
#}}}: _changes

_remoteVisible() { #{{{
  # $1 = tip author email, $2 = committer unix time. Remote-only branches are
  # shown when they are yours or recently active, unless -r asks for all.
  ((allRemotes)) && return 0
  [[ -n $userEmail && $1 == "$userEmail" ]] && return 0
  (($2 >= remoteSince))
}
#}}}: _remoteVisible

_hiddenRemotes() { #{{{
  # Number of remote-only branches the picker leaves out
  local name email when n=0
  local -A isLocal
  ((localOnly || allRemotes)) && { echo 0; return 0; }
  while IFS= read -r name; do isLocal[$name]=1; done < <(git branch --format='%(refname:short)')
  while read -r name email when; do
    [[ $name == "$remote" || $name == "$remote/HEAD" ]] && continue
    [[ -n ${isLocal[${name#"$remote"/}]-} ]] && continue
    _remoteVisible "$email" "$when" || n=$((n + 1))
  done < <(git for-each-ref --format='%(refname:short) %(authoremail:trim) %(committerdate:unix)' "refs/remotes/$remote")
  echo "$n"
}
#}}}: _hiddenRemotes

_pad() { #{{{
  # Sets REPLY to $1 right-padded with spaces to $2 characters (multibyte safe)
  REPLY="$1"
  while ((${#REPLY} < $2)); do REPLY+=" "; done
}
#}}}: _pad

_padc() { #{{{
  # Sets REPLY to colored text $1 padded to $3 characters, measured on its
  # plain form $2
  local pad=$(($3 - ${#2}))
  REPLY="$1"
  while ((pad-- > 0)); do REPLY+=" "; done
}
#}}}: _padc

_dirtyAll() { #{{{
  # Prints "total staged modified untracked conflicted<TAB>path" for every
  # worktree, checked in parallel (each line is one short write, so they
  # never interleave)
  local wt
  while IFS= read -r wt; do
    printf '%s\t%s\n' "$(git -C "$wt" status --porcelain 2>/dev/null | _statusCounts)" "$wt" &
  done < <(git worktree list --porcelain | sed -n 's/^worktree //p')
  wait
}
#}}}: _dirtyAll

_branchTable() { #{{{
  # Emits one line per branch, newest commit first:  name<TAB>display
  # display = "[*·]name  where  status  age  subject" (name colored by
  # state, see the usage legend), aligned, with
  # ANSI colors; status = sync plus the worktree's ~conflicted +staged
  # !modified ?untracked counts. $1 = branch to put first (base preselect).
  local front="${1-}"
  local -a names marks nameColors wheres stats statPlain ages subjects
  local -A isLocal remoteSha dirtyAt countsAt recent index
  local ref sha wt upstream track date when email subject name where state sync counts
  local n=0 i nameWidth=0 statWidth=0 dirty total path

  while IFS= read -r name; do isLocal[$name]=1; done \
    < <(git branch --format='%(refname:short)' | sed '/^(HEAD/d')
  while read -r name sha; do remoteSha[${name#"$remote"/}]="$sha"; done \
    < <(git for-each-ref --format='%(refname:short) %(objectname)' "refs/remotes/$remote" | sed "/^$remote /d")
  while IFS=$'\t' read -r counts path; do
    total="${counts%% *}"
    dirtyAt[$path]="$total" countsAt[$path]="${counts#* }"
  done < <(_dirtyAll)
  while IFS= read -r name; do [[ -n $name ]] && recent[$name]=1; done < <(_recent)
  _stateInit

  local -a refDirs=(refs/heads)
  ((localOnly)) || refDirs+=("refs/remotes/$remote")

  while IFS=$'\x1f' read -r ref sha wt upstream track date when email subject; do
    case $ref in
    refs/heads/*)
      name="${ref#refs/heads/}"
      dirty=0 counts=""
      if [[ -n $wt && -n $barePath ]]; then
        where="worktree"
        dirty="${dirtyAt[$wt]-0}" counts="${countsAt[$wt]-}"
      else
        where="local"
      fi
      _state "$name" "$sha" "$dirty"; state="$REPLY"
      _sync "$name" "$sha" "$upstream" "$track" "${remoteSha[$name]-}" "$state"; sync="$REPLY"
      ;;
    "refs/remotes/$remote/HEAD") continue ;;
    "refs/remotes/$remote/"*)
      name="${ref#refs/remotes/"$remote"/}"
      [[ -n ${isLocal[$name]-} ]] && continue
      _remoteVisible "$email" "$when" || continue
      where="remote" dirty=0 counts="" sync=""
      _state "$remote/$name" "$sha" 0; state="$REPLY"
      ;;
    *) continue ;;
    esac

    # --only=<filter> (the picker's alt keys) keeps one kind of branch
    case $onlyState in
    '') ;;
    gone) [[ $sync == gone ]] || continue ;;
    *) [[ $state == "$onlyState" ]] || continue ;;
    esac

    # The state colors the name instead of taking a column
    case $state in
    merged) nameColors[n]="$C_DIM" ;;
    new) nameColors[n]="${C_BOLD}${C_CYAN}" ;;
    *) nameColors[n]="$C_BOLD" ;;
    esac

    # status column, read like the prompt: sync first, then local changes
    _syncColor "$sync"; stats[n]="$REPLY" statPlain[n]="$sync"
    _changes "$counts"
    if [[ -n $PLAIN ]]; then
      stats[n]+="${sync:+ }$REPLY" statPlain[n]+="${sync:+ }$PLAIN"
    fi

    case $where in
    worktree) wheres[n]="${C_GREEN}worktree${C_RESET}" ;;
    local) wheres[n]="${C_BLUE}local   ${C_RESET}" ;;
    remote) wheres[n]="${C_MAGENTA}remote  ${C_RESET}" ;;
    esac

    marks[n]=" "
    [[ $name == "$currentBranch" ]] && marks[n]="${C_BOLD}*${C_RESET}"
    if [[ -n ${recent[$name]-} ]]; then marks[n]+="${C_DIM}·${C_RESET}"; else marks[n]+=" "; fi

    _age "$date"
    names[n]="$name" ages[n]="$REPLY" subjects[n]="${subject:0:60}"
    index[$name]=$n
    ((${#name} > nameWidth)) && nameWidth=${#name}
    ((${#statPlain[n]} > statWidth)) && statWidth=${#statPlain[n]}
    n=$((n + 1))
  done < <(git for-each-ref --sort=-committerdate \
    --format='%(refname)%1f%(objectname)%1f%(worktreepath)%1f%(upstream:short)%1f%(upstream:track,nobracket)%1f%(committerdate:relative)%1f%(committerdate:unix)%1f%(authoremail:trim)%1f%(subject)' \
    "${refDirs[@]}")
  _stateSave
  ((nameWidth > 48)) && nameWidth=48

  # Order: the requested front branch, then recently visited ones (latest
  # visit first), then the rest by commit date
  local -a order=()
  local -A placed
  if [[ -n $front && -n ${index[$front]-} ]]; then
    order+=("${index[$front]}"); placed[$front]=1
  fi
  while IFS= read -r name; do
    [[ -n $name && -n ${index[$name]-} && -z ${placed[$name]-} ]] || continue
    order+=("${index[$name]}"); placed[$name]=1
  done < <(_recent)
  for ((i = 0; i < n; i++)); do
    [[ -n ${placed[${names[i]}]-} ]] || order+=("$i")
  done

  local padName padStat
  for i in "${order[@]+"${order[@]}"}"; do
    name="${names[i]}"
    ((${#name} > 48)) && name="${name:0:47}…"
    _pad "$name" "$nameWidth"; padName="$REPLY"
    _padc "${stats[i]}" "${statPlain[i]}" "$statWidth"; padStat="$REPLY"

    printf '%s\t%s%s%s%s  %s  %s  %s%4s%s  %s%s%s\n' \
      "${names[i]}" \
      "${marks[i]}" "${nameColors[i]}" "$padName" "$C_RESET" \
      "${wheres[i]}" "$padStat" \
      "$C_DIM" "${ages[i]}" "$C_RESET" \
      "$C_DIM" "${subjects[i]}" "$C_RESET"
  done
}
#}}}: _branchTable

_userBinds() { #{{{
  # The --bind options from FZF_DEFAULT_OPTS, one per line. Every fzf call
  # passes them again after sw's own keys, so a personal mapping always wins.
  local opt next=0
  # shellcheck disable=SC2086 # word splitting is the point
  for opt in ${FZF_DEFAULT_OPTS-}; do
    if ((next)); then printf -- '--bind=%s\n' "$opt"; next=0
    elif [[ $opt == --bind=* ]]; then printf '%s\n' "$opt"
    elif [[ $opt == --bind ]]; then next=1; fi
  done
}
#}}}: _userBinds

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
    --color=header:-1:dim \
    "$@" "${userBinds[@]+"${userBinds[@]}"}"
}
#}}}: _fzf

_preview() { #{{{
  local name="$1" path dirty=0 ref sha where state upstream track mb line remoteSha
  name="${name%%[[:space:]]*}"
  path="$(_worktreePath "$name")"
  ref="$(_logRef "$name")"
  sha="$(git rev-parse -q --verify "$ref^{commit}" 2>/dev/null)" || { echo "(no commits)"; return 0; }
  [[ -n $path ]] && dirty="$(_dirtyCount "$path")"

  # Summary: where · state · sync · own commits
  _stateInit
  _state "$ref" "$sha" "$dirty"; state="$REPLY"
  if [[ -n $path ]]; then where="${C_GREEN}worktree${C_RESET}"
  elif _hasLocal "$name"; then where="${C_BLUE}local${C_RESET}"
  else where="${C_MAGENTA}remote only${C_RESET} $remote/$name"; fi
  line="$where"
  case $state in
  merged) line+="  ·  ${C_YELLOW}merged${C_RESET} into $baseRef ($MERGED)" ;;
  new) line+="  ·  ${C_CYAN}new${C_RESET}" ;;
  esac
  if _hasLocal "$name"; then
    IFS=$'\x1f' read -r upstream track < <(git for-each-ref \
      --format='%(upstream:short)%1f%(upstream:track,nobracket)' "refs/heads/$name")
    remoteSha="$(git rev-parse -q --verify "refs/remotes/$remote/$name" 2>/dev/null || true)"
    _sync "$name" "$sha" "$upstream" "$track" "$remoteSha" "$state"
    case $REPLY in
    '') [[ -n $remoteSha ]] && line+="  ·  in sync with $remote/$name" ;;
    gone | unpushed) line+="  ·  ${C_RED}$REPLY${C_RESET}" ;;
    *) _syncColor "$REPLY"; line+="  ·  $REPLY vs $remote/$name" ;;
    esac
  fi
  ((OWN > 0)) && line+="  ·  $OWN commit(s) not on $baseRef"
  if [[ -n $path ]]; then
    _changes "$(git -C "$path" status --porcelain 2>/dev/null | _statusCounts | cut -d' ' -f2-)"
    [[ -n $REPLY ]] && line+="  ·  $REPLY"
  fi
  printf '%s\n' "$line"

  if [[ -n $path ]]; then
    printf '%sworktree%s %s' "$C_BOLD" "$C_RESET" "$path"
    if ((dirty > 0)); then
      printf ' %s(%s uncommitted)%s\n' "$C_YELLOW" "$dirty" "$C_RESET"
      git -C "$path" -c color.status=always status --short | head -20
    else
      printf ' %s(clean)%s\n' "$C_GREEN" "$C_RESET"
    fi
    _carryCounts "$path"
    [[ -n $REPLY ]] && printf '%scarry%s %s\n' "$C_BOLD" "$C_RESET" "$REPLY"
  fi
  echo

  if [[ -z $baseSha ]]; then
    git log --oneline --decorate --color=always -n 40 "$sha"
    return 0
  fi
  # The branch's own commits, then a little of the base it forked from
  if ((OWN > 0)); then
    git log --oneline --decorate --color=always -n 40 "$baseSha..$sha"
  elif [[ $sha == "$baseSha" ]]; then
    printf '%sno commits of its own: at the tip of %s%s\n' "$C_DIM" "$baseRef" "$C_RESET"
  else
    printf '%sno commits of its own: its tip is on %s (%s)%s\n' "$C_DIM" "$baseRef" \
      "$(git log -1 --format=%cr "$sha")" "$C_RESET"
  fi
  mb="$(git merge-base "$baseSha" "$sha" 2>/dev/null || true)"
  if [[ -n $mb ]]; then
    printf '\n%s── %s ──%s\n' "$C_DIM" "$baseRef" "$C_RESET"
    git log --oneline --no-decorate --color=always -n 5 "$mb"
  fi
  _stateSave
}
#}}}: _preview

_header() { #{{{
  # One line: where we are, what the list leaves out, then the hint $1
  local where="$currentBranch" root="${repoRoot:-$PWD}" hidden line
  [[ -z $where ]] && where="(detached)"
  line="on ${where}  ·  ${root##*/}"
  hidden="$(_hiddenRemotes)"
  ((hidden > 0)) && line+="  ·  $hidden remote-only hidden"
  echo "$line${1:+  ·  $1}"
}
#}}}: _header

_keysRow() { #{{{
  # One legend row: $1 = color, $2 = symbol (padded by characters, not
  # bytes, so ⇡ and · line up), $3 = meaning
  _pad "$2" 10
  printf '  %s%s%s %s\n' "$1" "$REPLY" "$C_RESET" "$3"
}
#}}}: _keysRow

_keysHelp() { #{{{
  # Key cheat sheet shown in the preview pane by ctrl-/; $1 = switch | delete
  local b="$C_BOLD" r="$C_RESET" d="$C_DIM"
  printf '%skeys%s\n' "$b" "$r"
  if [[ $1 == delete ]]; then
    printf '  %-10s %s\n' "TAB" "mark several branches" "Enter" "delete the marked (or highlighted) branches"
  else
    printf '  %-10s %s\n' \
      "Enter" "switch (adds a worktree when there is none)" \
      "ctrl-x" "delete the highlighted or TAB-marked branches" \
      "ctrl-o" "create a new branch from the highlighted one" \
      "TAB" "mark several branches"
    printf '  %s\n' "a new name + Enter creates it from ${defaultBranch:-the default branch}"
  fi
  printf '  %-10s %s\n' "ctrl-r" "fetch all remotes and reload"
  [[ $1 == delete ]] || printf '  %-10s %s\n' "ctrl-a" "show every remote-only branch"
  printf '  %-10s %s\n' \
    "alt-m" "only merged branches" \
    "alt-g" "only branches whose remote is gone" \
    "alt-n" "only new branches" \
    "alt-0" "all branches again" \
    "ctrl-/" "back to the branch preview"
  local bind pair
  if ((${#userBinds[@]})); then
    printf '\n%syours%s %s(FZF_DEFAULT_OPTS, win over the above)%s\n' "$b" "$r" "$d" "$r"
    for bind in "${userBinds[@]}"; do
      bind="${bind#--bind=}"
      while IFS= read -r pair; do
        [[ -n $pair ]] && printf '  %-10s %s\n' "${pair%%:*}" "${pair#*:}"
      done < <(tr ',' '\n' <<<"$bind")
    done
  fi
  printf '\n%sname%s\n' "$b" "$r"
  _keysRow "$C_CYAN" "cyan" "new: no commits of its own yet"
  _keysRow "$d" "dim" "merged into $baseRef"
  _keysRow "$d" "·" "visited recently (listed first)"
  _keysRow "$b" "*" "current branch"
  printf '\n%sstatus%s\n' "$b" "$r"
  _keysRow "$C_GREEN" "⇡N ⇣M" "ahead / behind its own $remote branch (blank = in sync)"
  _keysRow "$C_RED" "unpushed" "commits on no remote branch"
  _keysRow "$C_RED" "gone" "its remote branch was deleted"
  _keysRow "$C_RED" "~N" "conflicts"
  _keysRow "$C_YELLOW" "+N" "staged"
  _keysRow "$C_YELLOW" "!N" "modified"
  _keysRow "$C_BLUE" "?N" "untracked"
}
#}}}: _keysHelp

_keysToggle() { #{{{
  # fzf transform for ctrl-/: swap the preview between the branch and the
  # key cheat sheet ($1 = switch | delete), tracked by the preview label
  local self
  self="$(printf '%q' "$0")"
  if [[ ${FZF_PREVIEW_LABEL-} == " keys " ]]; then
    printf '%s' "change-preview-label()+change-preview($self --preview {1})"
  else
    printf '%s' "change-preview-label( keys )+change-preview($self --keys=$1)"
  fi
}
#}}}: _keysToggle

_filterArgs() { #{{{
  # $1 = reload command. Prints fzf arguments, one per line: alt-m/g/n narrow
  # the list to merged, gone or new branches and name the filter in the
  # prompt, alt-0 shows everything again. Reloads read the filter back from
  # the prompt (fzf exports it as FZF_PROMPT), so ctrl-r keeps it.
  local cmd="$1" key kind
  for key in m:merged g:gone n:new; do
    kind="${key#*:}"
    printf -- '--bind\nalt-%s:reload(%s --only=%s)+change-prompt(%s> )\n' "${key%%:*}" "$cmd" "$kind" "$kind"
  done
  printf -- '--bind\nalt-0:reload(%s)+change-prompt(> )\n' "$cmd"
}
#}}}: _filterArgs

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
  local -a targets=("$@") dirtyWts=()
  local -A force
  local t p path dirty unpushed summary="" leaving=0 rc=0

  ((${#targets[@]})) || _die "No branch selected!"
  _stateInit

  for t in "${targets[@]}"; do
    [[ $t == "$defaultBranch" ]] && _die "Refusing to delete the default branch '$t'."
    _hasLocal "$t" || _die "'$t' is not a local branch (remote branches are not deleted)."
    path="$(_worktreePath "$t")"
    dirty=0
    [[ -n $path ]] && dirty="$(_dirtyCount "$path")"
    summary+="   $t"
    _state "$t" "$(git rev-parse "refs/heads/$t")" "$dirty"
    case $REPLY in
    merged) summary+="  ${C_YELLOW}merged ($MERGED)${C_RESET}" ;;
    new) summary+="  ${C_CYAN}new${C_RESET}" ;;
    *) ((OWN > 0)) && summary+="  ${C_RED}not merged (+$OWN)${C_RESET}" ;;
    esac
    if [[ -n $path ]]; then
      summary+="  (worktree"
      if ((dirty > 0)); then
        summary+=", ${C_YELLOW}${dirty} uncommitted change(s)${C_RESET}"
        dirtyWts+=("$t")
      fi
      summary+=")"
      [[ $PWD == "$path" || $PWD == "$path"/* ]] && leaving=1
    fi
    # Commits reachable from the branch but from no remote-tracking ref are
    # lost with it, unless they already landed on the base (squash merges)
    if [[ $REPLY != merged ]]; then
      unpushed="$(git rev-list --count "$t" --not --remotes 2>/dev/null || echo 0)"
      ((unpushed > 0)) && summary+="  ${C_RED}${unpushed} commit(s) not on any remote${C_RESET}"
    fi
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
  _stateSave
  if ((${#dirtyWts[@]})); then
    _msg "${C_YELLOW}Uncommitted changes would be discarded in:${C_RESET} ${dirtyWts[*]}"
    _prompt "Discard them (${#dirtyWts[@]} worktree(s))?"
    for t in "${dirtyWts[@]}"; do force[$t]=1; done
  fi

  # Leave any worktree before removing it so git never runs from a deleted cwd
  [[ -n $repoRoot ]] && cd "$repoRoot"

  for t in "${targets[@]}"; do
    path="$(_worktreePath "$t")"
    if [[ -n $path ]]; then
      # Only worktrees whose changes were explicitly given up are forced
      if [[ -n ${force[$t]-} ]]; then
        git worktree remove -f "$path" || { rc=1; continue; }
      else
        git worktree remove "$path" || { rc=1; continue; }
      fi
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
  # One line per worktree: branch, dirty count, state, sync, carry, path
  local wt br dirty counts changes upstream track syncPlain sha remoteSha mark state width=0 i
  local -a wts=() brs=()
  while IFS=$'\t' read -r wt br; do
    wts+=("$wt"); brs+=("$br")
    ((${#br} > width)) && width=${#br}
  done < <(_worktrees)
  ((${#wts[@]})) || _die "No worktrees."
  _stateInit

  for ((i = 0; i < ${#wts[@]}; i++)); do
    wt="${wts[i]}" br="${brs[i]}"
    mark=" "
    [[ $br == "$currentBranch" ]] && mark="*"
    counts="$(git -C "$wt" status --porcelain 2>/dev/null | _statusCounts)"
    dirty="${counts%% *}"
    IFS=$'\x1f' read -r upstream track sha < <(git for-each-ref \
      --format='%(upstream:short)%1f%(upstream:track,nobracket)%1f%(objectname)' "refs/heads/$br")
    remoteSha="$(git rev-parse -q --verify "refs/remotes/$remote/$br" 2>/dev/null || true)"
    _state "$br" "$sha" "$dirty"; state="$REPLY"
    _sync "$br" "$sha" "$upstream" "$track" "$remoteSha" "$state"
    syncPlain="$REPLY"
    _syncColor "$syncPlain"; _padc "$REPLY" "$syncPlain" 9; track="$REPLY"
    case $state in
    merged) state="${C_YELLOW}merged${C_RESET}" ;;
    new) state="${C_CYAN}new   ${C_RESET}" ;;
    *) state="      " ;;
    esac
    _changes "${counts#* }"
    if [[ -n $PLAIN ]]; then _padc "$REPLY" "$PLAIN" 14; else _padc "${C_GREEN}clean${C_RESET}" clean 14; fi
    changes="$REPLY"
    _pad "$br" "$width"
    printf '%s%s%s%s  %s  %s  %s%s' "$C_BOLD" "$mark" "$REPLY" "$C_RESET" "$state" "$track" "$changes" "$C_RESET"
    _carryCounts "$wt"
    [[ -n $REPLY ]] && printf '  carry: %s' "$REPLY"
    printf '  %s%s%s\n' "$C_DIM" "$wt" "$C_RESET"
  done
  _stateSave
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
      --preview "$(_previewFileCmd '{1}'"/$1")" --preview-window="right:60%,wrap" \
      "${userBinds[@]+"${userBinds[@]}"}" |
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
      --expect=ctrl-s,ctrl-o,ctrl-t,ctrl-x \
      --preview "$(_previewFileCmd '{3}')" --preview-window="right:50%,wrap,<120(down:50%)")" || true
  [[ -n $out ]] || return 0
  key="${out%%$'\n'*}"
  case $key in
  ctrl-s) echo "link" ;;
  ctrl-o) echo "copy" ;;
  ctrl-t) echo "detach" ;;
  ctrl-x) echo "forget" ;;
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
  [[ $1 == *d* ]] && hint+="  ctrl-t detach"
  [[ $1 == *f* ]] && hint+="  ctrl-x forget"
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
# Merge state is judged against the remote default branch: a stale local
# default would hide anything merged since the last pull.
baseRef="$defaultBranch"
[[ -n $defaultBranch ]] && _hasRemote "$defaultBranch" && baseRef="$remote/$defaultBranch"
userEmail="$(git config --get user.email 2>/dev/null || true)"
remoteSince=$(($(date +%s) - $(_cfg remoteAge 14) * 86400))
mapfile -t userBinds < <(_userBinds)
readonly barePath repoRoot currentBranch remote defaultBranch baseRef userEmail remoteSince userBinds

if [[ -n $keysToggle ]]; then
  _keysToggle "$keysToggle"
  exit 0
fi

if [[ -n $keysMode ]]; then
  _keysHelp "$keysMode"
  exit 0
fi

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
  hidden="$(_hiddenRemotes)"
  ((hidden > 0)) && _msg "$hidden remote-only branch(es) hidden, -r shows all"
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

# Reload command for the pickers' keys; the active alt filter is read back
# from the prompt so a reload keeps it
tableFlags=""
((localOnly)) && tableFlags+=" -L"
((allRemotes)) && tableFlags+=" -r"
tableCmd="$(printf '%q' "$0") --table$tableFlags --only=\"\${FZF_PROMPT%> }\""

if ((deleteBranch)); then
  if [[ -n $branch ]]; then
    _delete "$branch"
  else
    mapfile -t filterArgs < <(_filterArgs "$(printf '%q' "$0") --table$tableFlags")
    mapfile -t picked < <(
      _branchTable | _fzf --multi "${filterArgs[@]}" \
        --bind "ctrl-r:reload(git fetch --all --prune >/dev/null 2>&1; $tableCmd)" \
        --bind "ctrl-/:transform($(printf '%q' "$0") --keys-toggle=delete)" \
        --header "$(_header "delete  ·  TAB multi  ·  ctrl-/ keys")" | cut -f1
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
keys="ctrl-/ keys"
exclude="SW_EXCLUDE=$(printf '%q' "$currentBranch")"
mapfile -t filterArgs < <(_filterArgs "$exclude $(printf '%q' "$0") --table$tableFlags")
allHeader="$(allRemotes=1 _header "$keys")"
out="$(_branchTable | awk -F'\t' -v cur="$currentBranch" '$1 != cur' |
  _fzf --multi --print-query --expect=ctrl-x,ctrl-o "${filterArgs[@]}" \
    --bind "ctrl-r:reload(git fetch --all --prune >/dev/null 2>&1; $exclude $tableCmd)" \
    --bind "ctrl-a:reload($exclude $tableCmd -r)+change-header:$allHeader" \
    --bind "ctrl-/:transform($(printf '%q' "$0") --keys-toggle=switch)" \
    --header "$(_header "$keys")")" || rc=$?

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
