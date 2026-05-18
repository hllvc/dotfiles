#!/usr/bin/env bash
set -euo pipefail

NEWSYSLOG_DEST="/etc/newsyslog.d/com.hllvc.tmux-autosave.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "${HOME}/Library/Logs"

if ! command -v sleepwatcher &>/dev/null; then
  echo "Installing sleepwatcher…"
  brew install sleepwatcher
else
  echo "sleepwatcher already installed ($(sleepwatcher --version 2>/dev/null || true))"
fi

echo "Installing newsyslog config → ${NEWSYSLOG_DEST}"
sudo cp "${SCRIPT_DIR}/newsyslog.conf" "$NEWSYSLOG_DEST"
sudo chown root:wheel "$NEWSYSLOG_DEST"
sudo chmod 644 "$NEWSYSLOG_DEST"

echo "Verifying (dry run):"
sudo newsyslog -nv 2>&1 | grep "tmux-autosave" || echo "  (no rotation needed yet)"

echo "Done."
