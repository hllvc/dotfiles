#!/usr/bin/env bash

set -eo pipefail

JIRA_CONFIG="$HOME/.config/.jira/.config.yml"
ROOT_DIR="$HOME/Git/ProjectsList" # directory with list of projects
OPTION_LIST=("todo" "bl" "done" "status")
PROJECT_LIST=("proj1" "proj2") # project short names, jira prefix

if [[ $* =~ -h ]]; then
  echo "j [${PROJECT_LIST[*]}] [${OPTION_LIST[*]}]" && return 2
fi

project=${1:-$(echo "${PROJECT_LIST[@]}" | tr ' ' '\n' | fzf | tr '[:lower:]' '[:upper:]')}
option=${2:-$(echo "${OPTION_LIST[@]}" | tr ' ' '\n' | fzf)}

if [[ ${PWD%/*} =~ $ROOT_DIR.* ]]; then
  poject_directory="${PWD##*/}"
else
  cd "$ROOT_DIR"
  poject_directory="$(ls | fzf)"
  cd "$poject_directory"
fi

jira_config_project="$JIRA_CONFIG.${project}"
jira_config="$JIRA_CONFIG"

# set active project config
command mv "$jira_config" "$jira_config".old
command cp "$jira_config_project" "$jira_config"

case $option in
  done)
    issue_key=$(\
      jira sprint list \
        --current \
        -a"$(jira me)" \
        --plain \
        --no-headers \
        -q "status not in ('To Do', Done)" \
        --columns key,status,summary \
        | fzf --preview='jira issue view {1}' --preview-window=up | cut -f1 \
      )
    [[ -n $issue_key ]] && jira issue move "$issue_key" "Done"
    ;;
  bl)
    sprint=$(\
      jira sprint list \
        --table \
        --plain \
        --no-headers \
        | grep active | cut -f 1)
    issue_key=$(\
      jira issues list \
        -a"$(jira me)" \
        --plain \
        --no-headers \
        -s"To Do" \
        --columns key,status,summary \
        | fzf --preview='jira issue view {1}' --preview-window=up | cut -f1 \
      )
    [[ -n $sprint && -n $issue_key ]] && jira sprint add "$sprint" "$issue_key"
    issue_key=$(\
      jira sprint list \
        --current \
        -a"$(jira me)" \
        --plain \
        --no-headers \
        -s"To Do" \
        --columns key,status,summary \
        | fzf --preview='jira issue view {1}' --preview-window=up | cut -f1 \
      )
    ;;
  todo)
    issue_key=$(\
      jira sprint list \
        --current \
        -a"$(jira me)" \
        --plain \
        --no-headers \
        -s"To Do" \
        --columns key,status,summary \
        | fzf --preview='jira issue view {1}' --preview-window=up | cut -f1 \
      )
    if [[ -n $issue_key ]]; then
      git switch develop
      git stash -m "Saved by jira.sh before $issue_key" --include-untracked
      git pull --rebase origin develop
      git checkout -b "$issue_key" develop
      jira issue move "$issue_key" "In Progress"
    fi
    ;;
  status)
    branch_name=$(git branch --show-current)
    branch_prefix="${branch_name%%-*}"
    branch_number="${branch_name##*-}"
    if ! [[ $branch_prefix =~ [[:alpha:]] && $branch_number =~ [[:digit:]] ]]; then
      branch_name="$(git branch \
        | grep -E "[[:alpha:]].*-[[:digit:]]" \
        | fzf --header "Invalid branch name: $branch_name" \
        | tr -d " ")" # remove empty spaces
      branch_prefix="${branch_name%%-*}"
      branch_number="${branch_name##*-}"
    fi
    jira issue view "$branch_name"
    # jira sprint list \
    #   --current \
    #   -a"$(jira me)" \
    #   --plain \
    #   --no-headers \
    #   -s"To Do" \
    #   --columns key,status,summary \
    #   | fzf --preview='jira issue view {1}' --preview-window=up
    ;;
  # merge)
  #   swpr $1 && gh prm
  #   [[ $? != 0 ]] && return 2
  #   issue_key=$(git branch --show-current)
  #   issue_prefix=$(echo $issue_tag | tr '-' '\n' | head -n1)
  #   issue_number=$(echo $issue_tag | tr '-' '\n' | head -n2)
  #   [[ $issue_prefix =~ [[:alpha:]] && $issue_number =~ [[:digit:]] ]] && jira issue move $issue_key
  #   [[ $? != 0 ]] && echo "Unable to automatically move Jira ticket. Branch/Issue name: $issue_key"
  #   ;;
esac
