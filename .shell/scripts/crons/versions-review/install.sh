#!/usr/bin/env bash
set -euo pipefail

mkdir -p "${HOME}/Library/Logs/com.hllvc.versions-review"
mkdir -p "${HOME}/Library/Caches/com.hllvc.versions-review"

for tool in jq alerter; do
  if ! command -v "$tool" &>/dev/null && [[ ! -x "$HOME/.local/bin/$tool" ]]; then
    echo "WARNING: $tool not found — review.sh needs it" >&2
  fi
done
if [[ ! -x "$HOME/.local/bin/claude" ]]; then
  echo "WARNING: ~/.local/bin/claude not found — review.sh runs it headless" >&2
fi

echo "Done. Load the agent: ./dotctl agents load versions-review"
