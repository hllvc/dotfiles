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

_prompt() { #{{{
  local message="$1"

  read -n 1 -r -p ">> $message [y/N]: " yn
  case $yn in
    "y" | "Y")
      return
      ;;
    *)
      exit 1
      ;;
  esac
}
#}}}: _prompt

_cutSpaces() { #{{{
  cat | tr -d ' '
}
#}}}: _cutSpaces

_formatBranch() { #{{{
  # cat | tr '/' ' ' | tr -d '*+' | cut -d' ' -f3
  cat | tr -d '*+' | cut -d' ' -f3
}
#}}}: _formatBranch

_ifWorktreeSetup() { #{{{
  git worktree list | grep -q "(bare)"
  return $?
}
#}}}: _ifWorktreeSetup

_gitBranchList() { #{{{
  git branch $@
}
#}}}: _gitBranchList

_gitBranch() { #{{{
  if _ifWorktreeSetup && (( ! fetchAll )); then
    _gitBranchList | grep "[+*].*"
  else
    _gitBranchList $@
  fi
}
#}}}: _gitBranch

_getBranches() { #{{{
  if (( fetchAll && deleteBranch )); then
    echo "Cannot use -d on remote branch."
    exit 1
  elif (( fetchAll )); then
    _gitBranch -a
  else
    _gitBranch
  fi
}
#}}}: _getBranches

_fzf() { #{{{
  cat | _cutSpaces | _formatBranch | fzf \
    --no-sort \
    --track \
    --ansi \
    --layout=reverse-list \
    --preview 'git log --oneline {}'
}
#}}}: _fzf

_gitRebase() { #{{{
  git pull --rebase origin "$1" >/dev/null
}
#}}}: _gitRebase

# _gitFetch() { #{{{
#   git fetch -pP "${1##remotes/}"
#   branch="${1##*/}"
# }
# #}}}: _gitFetch

_getHeadBranch() { #{{{
  git remote show origin | grep -o "HEAD branch: .*" | cut -d':' -f2 | tr -d ' \n'
}
#}}}: _getHeadBranch

_getWorktreePath() { #{{{
  local branch="\[$1\]"

  if [[ "$branch" == "\[\]" ]]; then
    branch="(bare)"
  fi

  git worktree list \
    | grep "$branch" \
    | awk '{print $1}' \
    | tr -d "\n"
}
#}}}: _getWorktreePath

_addBranchToWorktree() { #{{{
  local -n worktreePath="$1"
  local branch="$2"
  local headBranch="$3"

  # If newBranch contains "/" in the name, replace with "-"
  # This is required so worktree does not get created nested
  # Usually used with feat/feature-name, fix/bugfix-name branch names
  # Will result in worktree path named like feat-feature-name, fix-bugfix-name
  worktreePath="${branch/\//-}"

  cd "$(_getWorktreePath)/.." || exit 1

  # If headBranch is passed, we assume that we want a new branch based on headBranch
  # Otherwise, just create new worktree path with existing branch
  if [[ -n "$headBranch" ]]; then
    git worktree add -b "$branch" "$worktreePath" "$headBranch" >/dev/null
  else
    git worktree add "$worktreePath" "$branch" >/dev/null
  fi
  worktreePath="$(_getWorktreePath "$branch")"
}
#}}}: _addBranchToWorktree

_createBranch() { #{{{
  local newBranch newBranchWorktreePath headBranch currentBranch currentWorktreePath

  # Get head branch which will be used as base for new branch.
  headBranch="$(_getBranches | _fzf)"
  if [[ -z "$headBranch" ]]; then
    echo "No branch selected!"
    exit 1
  fi
  readonly headBranch

  # Get active branch name and worktree path of the branch
  currentBranch="$(git branch --show-current)"
  if [[ -n "$currentBranch" ]]; then
    currentWorktreePath="$(_getWorktreePath "$currentBranch")"
  fi
  readonly currentBranch currentWorktreePath

  # Prompt for new branch name
  read -r -p ">> New branch: " newBranch
  if [[ -z "$newBranch" ]]; then
    echo "Branch name cannot be empty!"
    exit 1
  fi
  readonly newBranch

  if _ifWorktreeSetup; then
    # Switch to .bare path
    # cd "$(_getWorktreePath)" || exit 1
    # if [[ -n "$currentWorktreePath" ]]; then
    #   cd "${currentWorktreePath/$currentBranch//}" || exit 1
    # fi

    # read -r -p ">> Worktree Directory (default: $dirBranch): " dirBranch
    # git worktree add -b "$newBranch" "$newBranchWorktreePath" "$headBranch" >/dev/null
    _addBranchToWorktree newBranchWorktreePath "$newBranch" "$headBranch"
    cd "$newBranchWorktreePath" || exit 1
    _gitRebase "$headBranch"
    echo "$PWD"
    exit 0
  else
    git checkout -b "$newBranch" "$headBranch"
  fi
}
#}}}: _createBranch

_deleteBranch() { #{{{
  local branchToDelete="$1"
  local worktreePath activeBranch exitCode

  activeBranch="$(git branch --show-current)"

  if (( deleteBranch )); then
    _prompt "Delete branch: $branchToDelete"
    if _ifWorktreeSetup; then
      # If the activeBranch is same as branchToDelete,
      # go back once in the directory tree.
      # This will prevent being stuck in deleted path.
      [[ "$activeBranch" == "$branchToDelete" ]] && cd ..

      worktreePath="$(_getWorktreePath "$branchToDelete")"
      git worktree remove "$worktreePath" -f
      exitCode="$?"
    fi
    git branch -D "$branchToDelete" >&2 >/dev/null
    exitCode="$((exitCode+$?))"

    if ((exitCode > 0)); then
      exit 1
    fi

    return 0

    # If the activeBranch is same as branchToDelete,
    # return to the ${repo}/.bare directory.
    # After deleting branch, it removes working directory.
    # This will stuck user in deleted path,
    # and prevent navigating.
    # [[ "$activeBranch" == "$branchToDelete" ]] && _getWorktreePath
    # [[ "$activeBranch" == "$branchToDelete" ]] && echo "$PWD"
    # TODO: Add flag to enable deleting remote branches
    # git push origin --delete "$branch"
  fi

  return 1
}
#}}}: _deleteBranch

_isOriginBranch() { #{{{
  local branch="$1"

  if echo "$branch" | grep "remotes/origin" >/dev/null; then
    return 1
  fi

  return 0
}
#}}}: _isOriginBranch

(( fetchAll )) && git fetch --all
(( gitList )) && _getBranches && exit 0
(( createBranch )) && _createBranch

branch="$(_getBranches | _fzf)"
if [[ -z "$branch" ]]; then
  echo "No branch selected!"
  exit 2
fi

if _deleteBranch "$branch"; then
  cd "$(_getWorktreePath)/.." || exit 1
  echo "$PWD"
  exit 0
fi

# (( $(_isOriginBranch "$branch") )) && _gitFetch "$branch"

if _ifWorktreeSetup; then
  declare currentWorktreePath newWorktreePath workingPath
  declare newWorktreePath

  # Get current working path
  currentWorktreePath="$(_getWorktreePath "$(git branch --show-current)")"
  # Get working path of desired branch
  newWorktreePath="$(_getWorktreePath "$branch")"
  # Replace current working path base with new working path
  # This will perserve nested directories
  workingPath="${PWD/$currentWorktreePath/$newWorktreePath}"

  # If new working path exists, including nested directories, go there
  # Otherwise, if new worktree path existsing as it is, go there
  # In any other case, create new worktree path with new branch
  if [[ -n "$newWorktreePath" && -e "$workingPath" && "$workingPath" =~ .*$newWorktreePath.* ]]; then
    echo "$workingPath"
  elif [[ -e "$newWorktreePath" ]]; then
    echo "$newWorktreePath"
  else
    _addBranchToWorktree newWorktreePath "${branch##remotes/origin/}"
    echo "$newWorktreePath"
  fi
  exit 0

  # (( $(_isOriginBranch "$branch") )) && _gitRebase "$branch"
  # _gitRebase "$branch"

  # if [[ -e "$workingPath" && "$workingPath" =~ .*$newWorktreePath.* ]]; then
  #   echo "$workingPath"
  # else
  #   echo "$newWorktreePath"
  # fi
else
  git switch "$branch"
  # _gitRebase "$branch"
  # (( $(_isOriginBranch "$branch") )) && _gitRebase "$branch"
fi
