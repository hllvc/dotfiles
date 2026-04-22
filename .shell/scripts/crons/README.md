# crons

Scheduled user-level jobs. Each cron is a directory under `crons/` with its own runtime entrypoint, LaunchAgent plist (in [`.config/launch-agents/`](../../../.config/launch-agents/)), and — optionally — an `install.sh` for one-time system setup.

[Back to scripts](../)

## Contract

A cron directory is picked up by `./dotctl crons install` if it contains an `install.sh`. Scripts are invoked with `cwd` set to their own directory, so `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` works as expected.

Drop a new folder with an `install.sh` and `dotctl` will run it on the next install pass — no edit to `dotctl` needed.

The LaunchAgent side is orthogonal: any `*.plist` in `.config/launch-agents/` is loaded by `./dotctl agents load`.

## Crons

| Directory | Description |
|-----------|-------------|
| `memory-pressure/` | Samples `memory_pressure` every 5 minutes via `com.hllvc.memory-pressure` LaunchAgent; logs to `~/Library/Logs/com.hllvc.memory-pressure.log` and fires an `alerter` notification below 40% free. `install.sh` writes a `newsyslog.d` rotation rule (requires sudo). |
