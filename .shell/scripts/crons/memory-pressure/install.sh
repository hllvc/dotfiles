#!/usr/bin/env bash
set -euo pipefail

NEWSYSLOG_DEST="/etc/newsyslog.d/com.hllvc.memory-pressure.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "${HOME}/Library/Logs"

echo "Installing newsyslog config → ${NEWSYSLOG_DEST}"
sudo cp "${SCRIPT_DIR}/newsyslog.conf" "$NEWSYSLOG_DEST"
sudo chown root:wheel "$NEWSYSLOG_DEST"
sudo chmod 644 "$NEWSYSLOG_DEST"

echo "Verifying (dry run):"
sudo newsyslog -nv 2>&1 | grep "memory-pressure" || echo "  (no rotation needed yet)"

echo "Done."
