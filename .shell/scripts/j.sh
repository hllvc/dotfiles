#!/usr/bin/env bash

set -eo pipefail

ROOT_DIR="$HOME/Git/Bloomteq" # directory with list of projects
OPTION_LIST=("todo" "bl" "done" "status")

export JIRA_API_TOKEN="$(op read "op://Bloomteq General/Jira API Key/credential")"
export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS --preview-window=up:80%"

option=${1:-$(echo "${OPTION_LIST[@]}" | tr ' ' '\n' | fzf)}

if [[ ${PWD%/*} =~ $ROOT_DIR.* ]]; then
  poject_directory="${PWD##*/}"
else
  cd "$ROOT_DIR"
  poject_directory="$(ls | fzf)"
  cd "$poject_directory"
fi

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
        | fzf --preview='jira issue view {1}' | cut -f1 \
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
        | fzf --preview='jira issue view {1}' | cut -f1 \
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
        | fzf --preview='jira issue view {1}' | cut -f1 \
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
        | fzf --preview='jira issue view {1}' | cut -f1 \
      )
    if [[ -n $issue_key ]]; then
      remote_base="$(basename "$(git ls-remote --symref origin HEAD | grep -o "refs/heads/\S*" | tr -d '\n')")"
      git worktree add -b "$issue_key" "$issue_key" "$remote_base"
      jira issue move "$issue_key" "Todo to In progress"
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
    #   | fzf --preview='jira issue view {1}'
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
