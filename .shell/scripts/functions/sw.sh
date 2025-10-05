#!/usr/bin/env bash

# set -eo pipefail

for arg; do
  case $arg in
    a|-a) fetchAll=1; shift ;;
    d|-d) deleteBranch=1; shift ;;
    ls|l|-l) gitList=1; shift ;;
    [cn]|-[cn]) createBranch=1; shift ;;
    *) git switch "$*"; exit 0 ;;
  esac
done

_prompt() {
  message="$1"
  while true; do
    read -n 1 -r -p ">> $message [y/N]: " yn
    case $yn in
      "y" | "Y")
        return
        ;;
      *)
        exit 1
        ;;
    esac
  done
}

_cutSpaces() {
  cat | tr -d ' '
}

_formatBranch() {
  # cat | tr '/' ' ' | tr -d '*+' | cut -d' ' -f3
  cat | tr -d '*+' | cut -d' ' -f3
}

_ifWorktreeSetup() {
  git worktree list | grep -q "(bare)"
  return $?
}

_gitBranchList() {
  git branch $@
}

_gitBranch() {
  if _ifWorktreeSetup && (( ! fetchAll )); then
    _gitBranchList | grep "[+*].*"
  else
    _gitBranchList $@
  fi
}

_getBranches() {
  if (( fetchAll && deleteBranch )); then
    echo "Cannot use -d on remote branch."
    exit 1
  elif (( fetchAll )); then
    _gitBranch -a
  else
    _gitBranch
  fi
}

_fzf() {
  cat | _cutSpaces | _formatBranch | fzf \
    --no-sort \
    --track \
    --ansi \
    --layout=reverse-list \
    --preview 'git log --oneline {}'
}

_gitRebase() {
  git pull --rebase origin "$1" >/dev/null
}

_gitFetch() {
  git fetch -pP $(echo ${1##remotes/})
  branch="${1##*/}"
}

_getHeadBranch() {
  git remote show origin | grep -o "HEAD branch: .*" | cut -d':' -f2 | tr -d ' \n'
}

_createBranch() {
  local newBranch dirBranch
  # local headBranch="$(_getHeadBranch)"
  local headBranch="$(_getBranches | _fzf)"
  if [[ -z "$headBranch" ]]; then
    echo "No branch selected!"
    exit 1
  fi
  local currentBranch="$(git branch --show-current)"
  if [[ -n "$currentBranch" ]]; then
    local currentWorktreePath="$(_getWorktreePath "$(git branch --show-current)")"
  fi

  read -r -p ">> New branch: " newBranch
  if [[ -z "$newBranch" ]]; then
    echo "Branch name cannot be empty!"
    exit 1
  fi

  if _ifWorktreeSetup; then
    if [[ -n "$currentWorktreePath" ]]; then
      cd "${currentWorktreePath/$currentBranch//}"
    fi
    dirBranch="${newBranch/\//-}"
    # read -r -p ">> Worktree Directory (default: $dirBranch): " dirBranch
    git worktree add -b "$newBranch" "$dirBranch" "$headBranch" >/dev/null
    cd "$dirBranch"
    # _gitRebase "$headBranch"
    echo "$PWD"
    exit 0
  else
    git checkout -b "$newBranch" "$headBranch"
  fi
}

_deleteBranch() {
  local branchToDelete="$1"
  local worktreePath=
  local activeBranch="$(_gitBranch --show-current)"

  if (( deleteBranch )); then
    _prompt "Delete branch: $branchToDelete"
    if _ifWorktreeSetup; then
      # If the activeBranch is same as branchToDelete,
      # go back once in the directory tree.
      # This will prevent being stuck in deleted path.
      [[ "$activeBranch" == "$branchToDelete" ]] && cd ..
      worktreePath="$(_getWorktreePath "$branchToDelete")"
      git worktree remove "$worktreePath" -f
    fi
    git branch -D "$branchToDelete" >&2
    # If the activeBranch is same as branchToDelete,
    # return to the ${repo}/.bare directory.
    # After deleting branch, it removes working directory.
    # This will stuck user in deleted path,
    # and prevent navigating.
    [[ "$activeBranch" == "$branchToDelete" ]] \
      && echo "$(_getWorktreePath)"
    # TODO: Add flag to enable deleting remote branches
    # git push origin --delete "$branch"
    exit 0
  fi
}

_isOriginBranch() {
  local branch="$1"
  if echo "$branch" | grep "remotes/origin" >/dev/null; then
    return 1
  fi
  return 0
}

_getWorktreePath() {
  local branch="\[$1\]"

  if [[ "$branch" == "\[\]" ]]; then
    branch="(bare)"
  fi

  git worktree list \
    | grep "$branch" \
    | awk '{print $1}' \
    | tr -d "\n"
}

(( gitList )) && _getBranches && exit 0
(( createBranch )) && _createBranch

branch="$(_getBranches | _fzf)"
if [[ -z "$branch" ]]; then
  echo "No branch selected!"
  exit 2
fi

_deleteBranch "$branch"

# (( $(_isOriginBranch "$branch") )) && _gitFetch "$branch"

if _ifWorktreeSetup; then
  readonly currentWorktreePath="$(_getWorktreePath "$(git branch --show-current)")"
  readonly newWorktreePath="$(_getWorktreePath "$branch")"
  readonly workingPath="${PWD/$currentWorktreePath/$newWorktreePath}"

  if [[ -e "$workingPath" && "$workingPath" =~ .*$newWorktreePath.* ]]; then
    cd "$workingPath"
  else
    cd "$newWorktreePath"
  fi

  # (( $(_isOriginBranch "$branch") )) && _gitRebase "$branch"
  # _gitRebase "$branch"

  if [[ -e "$workingPath" && "$workingPath" =~ .*$newWorktreePath.* ]]; then
    echo "$workingPath"
  else
    echo "$newWorktreePath"
  fi
else
  git switch "$branch"
  # _gitRebase "$branch"
  # (( $(_isOriginBranch "$branch") )) && _gitRebase "$branch"
fi
