#!/usr/bin/env bash

history \
  | fzf --tac --no-sort \
  | awk '{print $1}' \
  | tr -d "\n" \
  | tr -d "*" \
  | pbcopy
