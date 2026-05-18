# crons

Scheduled user-level jobs. Each cron is a directory under `crons/` with its own runtime entrypoint, LaunchAgent plist (in [`.config/launch-agents/`](../../../.config/launch-agents/)), and — optionally — an `install.sh` for one-time system setup.

[Back to scripts](../)

## Contract

A cron directory is picked up by `./dotctl crons install` if it contains an `install.sh`. Scripts are invoked with `cwd` set to their own directory, so `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` works as expected.

Drop a new folder with an `install.sh` and `dotctl` will run it on the next install pass — no edit to `dotctl` needed.

The LaunchAgent side is orthogonal: any `*.plist` in `.config/launch-agents/` is loaded by `./dotctl agents load`.

`_lib/` holds bash snippets shared between crons (`log.sh` for the bordered-block logger, `notify.sh` for `alerter` wrappers). It has no `install.sh` so `dotctl crons install` skips it.

## Crons

| Directory | Description |
|-----------|-------------|
| `homebrew-update/` | Runs daily at 10:00 via `com.hllvc.homebrew-update` LaunchAgent. Skips on battery or offline. Runs `brew update`, `upgrade`, `upgrade --cask --greedy`, `autoremove`, `cleanup -s`. Logs to `~/Library/Logs/com.hllvc.homebrew-update/main.log`; sticky alert on failure. `install.sh` writes a `sudoers.d` snippet (NOPASSWD for installer/file-ops) and a `newsyslog.d` rotation rule. |
| `memory-pressure/` | Samples `memory_pressure` every 5 minutes via `com.hllvc.memory-pressure` LaunchAgent; logs to `~/Library/Logs/com.hllvc.memory-pressure/main.log` and fires an `alerter` notification below 40% free. `install.sh` writes a `newsyslog.d` rotation rule (requires sudo). |
| `tmux-autosave/` | Idle-gated tmux session saver. Three save triggers: (1) `com.hllvc.tmux-autosave` timer fires every 30 min — saves when HID idle ≥ 30 s, force-saves after 90 min; (2) `~/.sleep` run by `sleepwatcher` (`com.hllvc.sleepwatcher`) before sleep/hibernate; (3) `daemon.sh` kept alive by `com.hllvc.tmux-shutdown-save` catches launchd `SIGTERM` on shutdown/reboot. All paths call `entrypoint.sh --force` (sleep/shutdown) or the normal idle-gated path (timer). Logs to `~/Library/Logs/com.hllvc.tmux-autosave/main.log`. Replaces `@continuum-save-interval` (disabled in `.tmux.conf`). Requires `brew install sleepwatcher`. `install.sh` writes a `newsyslog.d` rotation rule (requires sudo). |
| `tmux-warmup/` | Pre-starts the `work` and `personal` tmux servers at login (one plist per socket: `com.hllvc.{work,personal}.tmux`) so `tmux-continuum` auto-restore runs before the user attaches. Verifies the socket is up, counts restored sessions, logs to `~/Library/Logs/com.hllvc.tmux-warmup/main.log`, and fires an `alerter` notification on each launch (sticky on failure). `install.sh` writes a `newsyslog.d` rotation rule (requires sudo). |
