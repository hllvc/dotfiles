#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUDOERS_DEST="/etc/sudoers.d/com.hllvc.homebrew-update"
NEWSYSLOG_DEST="/etc/newsyslog.d/com.hllvc.homebrew-update.conf"

mkdir -p "${HOME}/Library/Logs/com.hllvc.homebrew-update"

echo "Validating sudoers file syntax..."
sudo visudo -cf "${SCRIPT_DIR}/sudoers"

echo "Installing sudoers rule → ${SUDOERS_DEST}"
sudo cp "${SCRIPT_DIR}/sudoers" "${SUDOERS_DEST}"
sudo chown root:wheel "${SUDOERS_DEST}"
sudo chmod 440 "${SUDOERS_DEST}"

echo "Installing newsyslog config → ${NEWSYSLOG_DEST}"
sudo cp "${SCRIPT_DIR}/newsyslog.conf" "${NEWSYSLOG_DEST}"
sudo chown root:wheel "${NEWSYSLOG_DEST}"
sudo chmod 644 "${NEWSYSLOG_DEST}"

echo "Verifying newsyslog (dry run):"
sudo newsyslog -nv 2>&1 | grep "homebrew-update" || echo "  (no rotation needed yet)"

echo "Done."
