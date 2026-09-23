#!/usr/bin/env bash
set -euo pipefail

NEWSYSLOG_DEST="/etc/newsyslog.d/com.hllvc.wifi-watchdog.conf"
# NOT com.hllvc.wifi-watchdog: sudo silently skips any file in an include
# directory whose name contains a "." or ends in "~" (it is how it avoids
# picking up .rpmsave/.dpkg-old leftovers). A dotted rule installs cleanly,
# passes visudo -c, and is then ignored — verify with `sudo -n`, not with ls.
SUDOERS_DEST="/etc/sudoers.d/com-hllvc-wifi-watchdog"
SUDOERS_LEGACY="/etc/sudoers.d/com.hllvc.wifi-watchdog"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "${HOME}/Library/Logs/com.hllvc.wifi-watchdog"
mkdir -p "${HOME}/Library/Caches/com.hllvc.wifi-watchdog"

# Only used for the bounce notification — the watchdog itself degrades quietly
# if it is missing.
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
sudo cp "${SCRIPT_DIR}/sudoers" "$SUDOERS_DEST"
sudo chown root:wheel "$SUDOERS_DEST"
sudo chmod 440 "$SUDOERS_DEST"

# Ask sudo what it would permit, rather than running the command: a plain
# `sudo -n <cmd>` succeeds on a warm timestamp from the sudo calls just above,
# which is precisely how a dead rule stays hidden.
echo "Verifying passwordless read:"
if sudo -n -l 2>/dev/null | grep -q 'NOPASSWD.*wdutil info'; then
  echo "  rule live → sudo -n wdutil info"
else
  echo "  WARNING: rule not in effect — the watchdog cannot read NSS" >&2
fi

echo "Installing newsyslog config → ${NEWSYSLOG_DEST}"
sudo cp "${SCRIPT_DIR}/newsyslog.conf" "$NEWSYSLOG_DEST"
sudo chown root:wheel "$NEWSYSLOG_DEST"
sudo chmod 644 "$NEWSYSLOG_DEST"

echo "Verifying (dry run):"
sudo newsyslog -nv 2>&1 | grep "wifi-watchdog" || echo "  (no rotation needed yet)"

echo "Done."
