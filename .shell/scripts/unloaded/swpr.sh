#!/usr/bin/env bash

set -eo pipefail

# cd "$1"
data=$(gh pr list -a@me --json title --json headRefName --json reviewDecision --jq '.[] | {title: "\(.title) \(.reviewDecision)", branch: .headRefName}')
echo "$data"
exit
[[ -z $data ]] && printf "\nThere are no open Pull Requests assigned to you." && exit 0
title=$(echo "$data" | jq -r '.title' | fzf --preview='echo {1} | tr -d ":" | xargs jira issue view' --preview-window=up)
branch=$(echo "$data" | jq -r ". | select(.title==\"$title\") | .branch")
git stash save
git switch "$branch"
git pull --rebase origin "$branch"
base=$(gh pr view --json baseRefName | jq -r '.baseRefName')
git pull --rebase origin "$base"
