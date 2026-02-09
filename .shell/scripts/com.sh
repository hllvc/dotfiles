#!/usr/bin/env bash

declare commit_prefix

readonly branch_name="$(git branch --show-current)"
readonly branch_prefix="$(echo "$branch_name" | cut -f1 -d'-')"
readonly branch_suffix="$(echo "$branch_name" | cut -f2 -d'-')"

if [[ "$1" == "-feat" ]]; then
  commit_prefix="feat"
  shift
elif [[ "$1" == "-fix" ]]; then
  commit_prefix="fix"
  shift
elif [[ "$1" == "-doc" ]]; then
  commit_prefix="docs"
fi
readonly commit_prefix

if [[ $branch_prefix =~ ^[[:alpha:]]+$ && $branch_suffix =~ ^[[:digit:]]+$ ]]; then
  if [[ -n "$commit_prefix" ]]; then
    git commit --no-verify -m "$commit_prefix(${branch_prefix}-${branch_suffix}): $*"
  else
    git commit --no-verify -m "${branch_prefix}-${branch_suffix}: $*"
  fi
else
  if [[ -n "$commit_prefix" ]]; then
    git commit --no-verify -m "$commit_prefix: $*"
  else
    git commit --no-verify -m "$*"
  fi
fi
