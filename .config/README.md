# .config

Application configuration files managed via GNU Stow.

[Back to root](../)

## Directories

| Directory | Description |
|-----------|-------------|
| `1Password/` | SSH agent configuration for 1Password integration |
| `ghostty/` | Ghostty terminal configuration, split into `font.conf`, `theme.conf`, `ui.conf`, `qol.conf` and `init.conf` (included by `config`; its `command` starts `tt.sh`, the tmux socket picker, in every window). `qol.conf` has the quick terminal (`cmd+shift+\``), `shift+enter` sending ESC-CR so Claude Code gets a newline, plain-text `cmd+c`, copy on select, and a notification when a long command finishes in an unfocused window. `no-tmux/` is a variant with its own keybinds that mirror tmux's `C-f` prefix |
| `karabiner/` | Keyboard remapping: Caps Lock acts as Escape, and with Caps held `H` `J` `K` `L` are the arrow keys, `U` `D` are Page Up / Down, and `Space` is a real Caps Lock; per keyboard, the grave key becomes left Shift, the ISO extra backslash key becomes grave, and right Option becomes right Control. `assets/complex_modifications/` has an alternate hyper-`JIKL` arrows rule that the active profile doesn't use |
| `gh/` | GitHub CLI config: ssh git protocol and aliases (`co` checks out a PR, `pro` creates a draft PR assigned to you, `prucp` copies a PR's URL) |
| `launch-agents/` | macOS LaunchAgents, loaded via `./dotctl agents load` (each has a cron or script under [`.shell/scripts/crons/`](../.shell/scripts/crons/)): tmux sockets (`com.hllvc.{work,personal}.tmux`), `tmux-autosave`, `tmux-shutdown-save`, `sleepwatcher`, `memory-pressure`, `wifi-watchdog`, `homebrew-update` (disabled for now; `brewup` replaces it), `versions-review` (daily update triage). `./dotctl agents list` shows which are loaded |
| [`nvim/`](nvim/) | Neovim configuration with lazy.nvim, LSP, snippets, and custom keymaps |
