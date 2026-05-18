#!/usr/bin/env bash
set -euo pipefail

NEWSYSLOG_DEST="/etc/newsyslog.d/com.hllvc.tmux-warmup.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "${HOME}/Library/Logs"

if ! command -v tmux &>/dev/null; then
  echo "Installing tmux…"
  brew install tmux
else
  echo "tmux already installed"
fi

if ! command -v alerter &>/dev/null; then
  echo "Installing alerter…"
  brew install vjeantet/tap/alerter
else
  echo "alerter already installed"
fi

echo "Installing newsyslog config → ${NEWSYSLOG_DEST}"
sudo cp "${SCRIPT_DIR}/newsyslog.conf" "$NEWSYSLOG_DEST"
sudo chown root:wheel "$NEWSYSLOG_DEST"
sudo chmod 644 "$NEWSYSLOG_DEST"

echo "Verifying (dry run):"
sudo newsyslog -nv 2>&1 | grep "tmux-warmup" || echo "  (no rotation needed yet)"

echo "Done."
