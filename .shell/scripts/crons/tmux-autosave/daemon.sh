#!/usr/bin/env bash
# Stays alive in the background (KeepAlive launchd plist).
# Traps SIGTERM to save tmux sessions before macOS shuts down or reboots.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_save_on_shutdown() {
  "$SCRIPT_DIR/entrypoint.sh" --force || true
}

trap '_save_on_shutdown; exit 0' TERM INT

while true; do
  sleep 86400 &
  wait "$!" || true
done
