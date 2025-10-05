#!/usr/bin/env bash

set -e

query=
env=""

time="5m"
filter=

if command -v fzf &>/dev/null; then
  hasFZF=1
fi

getNS() {
  local input="$1"
  local nsList="$2"

  if [[ -z "$nsList" ]]; then
    kubectl get --no-headers ns | awk '{print $1}' | grep ".*$input"
  else
    printf "$nsList" | grep ".*$input"
  fi
}

searchMenu() {
  local prompt="$1"

  if (( $hasFZF )); then
    query="$(echo "$env" | fzf)"
  else
    if [[ -n "$env" ]]; then
      echo
      echo "---"
      echo "$env"
      echo "---"
    fi
    read -r -p "$prompt" query
  fi
  env="$(getNS "$query" "$env")"
}

for arg; do
  case $arg in
    -t) time="$2"; shift 2 ;;
    -f) filter="$2"; shift 2 ;;
    -e) errors=1; shift 1 ;;
    *) query="$*" ;;
  esac
done

if [[ -z "$query" ]]; then
  if (( $hasFZF )); then
    env="$(getNS | fzf)"
  else
    searchMenu "Environment: "
  fi
else
  env="$(getNS "$query")"
fi

while (( $(echo "$env" | wc -l) != 1 )); do
  searchMenu "Filter: "
done

pod="$(kubectl -n "$env" get --no-headers po | awk '{print $1}' | fzf)"

echo
echo "---"
echo "Environment pod: $pod"
echo "Time buffer: $time"
echo "---"
echo

if (( $errors )); then
  filter="ERROR"
fi

if [[ -n $filter ]]; then
  kubectl -n "$env" logs "$pod" --since="$time" | grep "$filter"
  echo
  echo "---"
  echo "Filtered by: $filter"
else
  sleep 2
  kubectl -n "$env" logs "$pod" -f --since="$time"
fi
