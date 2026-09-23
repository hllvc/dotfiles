#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# NOT com.hllvc.homebrew-update: sudo silently skips any file in an include
# directory whose name contains a "." or ends in "~". A dotted rule installs
# cleanly, passes visudo -cf, and shows up in ls — and is then never read, so
# every cask needing root fell back to prompting for a password. Under launchd
# there is no tty, so those upgrades failed outright:
#   sudo: a terminal is required to read the password
#   Error: Problems with multiple casks
# Verify with `sudo -n`, never with ls.
SUDOERS_DEST="/etc/sudoers.d/com-hllvc-homebrew-update"
SUDOERS_LEGACY="/etc/sudoers.d/com.hllvc.homebrew-update"
NEWSYSLOG_DEST="/etc/newsyslog.d/com.hllvc.homebrew-update.conf"

mkdir -p "${HOME}/Library/Logs/com.hllvc.homebrew-update"

if ! command -v alerter &>/dev/null; then
  echo "Installing alerter…"
  brew install vjeantet/tap/alerter
else
  echo "alerter already installed"
fi

if [[ -e "$SUDOERS_LEGACY" ]]; then
  echo "Removing ignored dotted rule → ${SUDOERS_LEGACY}"
  sudo rm -f "$SUDOERS_LEGACY"
fi

echo "Validating sudoers file syntax..."
sudo visudo -cf "${SCRIPT_DIR}/sudoers"

echo "Installing sudoers rule → ${SUDOERS_DEST}"
sudo cp "${SCRIPT_DIR}/sudoers" "${SUDOERS_DEST}"
sudo chown root:wheel "${SUDOERS_DEST}"
sudo chmod 440 "${SUDOERS_DEST}"

# Ask sudo what it would permit, rather than running the command: a plain
# `sudo -n <cmd>` succeeds on a warm timestamp from the sudo calls just above,
# which is precisely how this rule stayed dead from May to September.
echo "Verifying passwordless escalation:"
if sudo -n -l 2>/dev/null | grep '/usr/sbin/installer' | grep 'NOPASSWD:' | grep -q 'SETENV:'; then
  echo "  rule live → sudo -n -E installer"
else
  echo "  WARNING: rule not in effect — cask upgrades needing root will fail" >&2
fi

echo "Installing newsyslog config → ${NEWSYSLOG_DEST}"
sudo cp "${SCRIPT_DIR}/newsyslog.conf" "${NEWSYSLOG_DEST}"
sudo chown root:wheel "${NEWSYSLOG_DEST}"
sudo chmod 644 "${NEWSYSLOG_DEST}"

echo "Verifying newsyslog (dry run):"
sudo newsyslog -nv 2>&1 | grep "homebrew-update" || echo "  (no rotation needed yet)"

echo "Done."
