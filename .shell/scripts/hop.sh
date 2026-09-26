#!/usr/bin/env bash

set -eo pipefail

readonly hostname="$(cat ~/.ssh/config | grep "^Host [^*]*[^*]$" | cut -d" " -f2 | fzf)"

if [[ -n "$hostname" ]]; then
  ssh $@ "$hostname"
fi
