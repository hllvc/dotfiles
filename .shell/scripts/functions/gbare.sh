#!/usr/bin/env bash

readonly REQUIRED_COMMANDS=(
  "gh"
  "fzf"
)

for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "Required command '$cmd' not found." >&2
    exit 1
  fi
done

_get_username() { #{{{
  gh auth status "$@" | grep "Logged in" | cut -d' ' -f9 | fzf -1
}
#}}}: _get_username

_switch_user() { #{{{
  local selected_user active_user

  selected_user="$(_get_username)"
  active_user="$(_get_username -a)"

  if [[ -z "$selected_user" ]]; then
    echo "No user selected."
    exit 2
  fi

  if [[ "$selected_user" != "$active_user" ]]; then
    gh auth switch -u "$selected_user"
  fi
}
#}}}: _switch_user

_choose_repo_for_org() { #{{{
  local -n repo_ref="$1"
  local owner="$2"
  local count="${3:-100}"

  repo_ref="$(gh repo list "$owner" \
    -L "$count" \
    --json "name" \
    --jq '.[].name' | fzf)"

  # shellcheck disable=2034
  # The repo_ref is only named reference.
  # Variable is passed to function by refernece, which is modified inside function.
  # After that, variable is set to readonly so it cannot be further changed.
  readonly repo_ref
}
#}}}: _choose_repo_for_org

_choose_org() { #{{{
  local -n org_ref="$1"
  local org_list

  org_list="$(gh org list)"
  org_ref="$(printf "%s\n%s" "$org_list" "$(_get_username)" | fzf)"

  # shellcheck disable=2034
  # The org_ref is only named reference.
  # Variable is passed to function by refernece, which is modified inside function.
  # After that, variable is set to readonly so it cannot be further changed.
  readonly org_ref
}
#}}}: _choose_org

main() { #{{{
  local repo_url repo_name

  if [[ -z "$1" ]] || (($# != 1)); then
    _switch_user

    _choose_org org
    if [[ -z "$org" ]]; then
      echo "No org selected."
      exit 2
    fi

    _choose_repo_for_org repo_name "$org"
    if [[ -z "$repo_name" ]]; then
      echo "No repo selected."
      exit 2
    fi

    repo_url="git@github.com:${org}/$repo_name"
  else
    repo_url="$1"
  fi
  readonly repo_url

  readonly repo_dir="${repo_name:-$(basename "${repo_url%.*}")}"

  git clone --bare "$repo_url" "$repo_dir"/.bare \
    && cd "$repo_dir" || exit 1

  echo "gitdir: ./.bare" > .git
  printf "\tfetch = +refs/heads/*:refs/remotes/origin/*" >> .bare/config

  default_branch="$(git branch --show-current)"
  readonly default_branch

  git worktree add "$default_branch" >&2

  echo "$(pwd)/$default_branch"
}
#}}}: _main

main "$@"
