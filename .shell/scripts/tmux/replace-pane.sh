#!/usr/bin/env bash
#
# Replace the current pane with a fresh login shell, in place.
#
# Uses `respawn-pane -k`, so the pane itself survives untouched — same %id, index,
# geometry, window and layout — while the process inside it is killed and a brand
# new shell is exec'd. cwd, pane title and the exported environment are carried
# over; scrollback is not (that's the point). Shell history needs no help:
# share_history means the old pane's commands are already in ~/.zsh_history
# before we kill it.
#
# If the pane was running one of the programs resurrect is configured to bring
# back (@resurrect-default-processes — editors and claude), it is relaunched in
# the replacement shell, inline strategies included: `claude` comes back as
# `claude --continue`. Anything else replaces to a bare prompt.
#
# Bound to prefix+C-r; also runnable directly (the `treplace` alias), optionally
# with an explicit target pane as $1.
set -uo pipefail

export TMUX_TMPDIR="${TMUX_TMPDIR:-$HOME/.tmux/sockets}"
env_dir="${TMUX_PANE_ENV_DIR:-$HOME/.tmux/pane-env}"

# Status line: tmux message when inside tmux, else just print to the terminal.
_say() {
  if [[ -n "${TMUX:-}" ]]; then
    tmux display-message "tmux-replace: $1" 2>/dev/null || true
  else
    printf 'tmux-replace: %s\n' "$1"
  fi
}

pane="${1:-${TMUX_PANE:-}}"
if [[ -z "$pane" ]]; then
  _say "not inside a tmux pane"
  exit 1
fi

# --- gather ------------------------------------------------------------------
# One call, newline-delimited: both the path and the title can contain spaces,
# so a space/TAB-delimited format would be ambiguous.
meta=()
while IFS= read -r line; do meta+=("$line"); done < <(
  tmux display-message -p -t "$pane" '#{pane_id}
#{pane_current_path}
#{pane_title}' 2>/dev/null
)

if (( ${#meta[@]} < 3 )); then
  _say "could not resolve pane ${pane}"
  exit 1
fi

pane_id="${meta[0]}"
pane_path="${meta[1]}"
pane_title="${meta[2]}"

[[ -d "$pane_path" ]] || pane_path="$HOME"

# --- program ------------------------------------------------------------------
# Reuse resurrect's own list, strategies and capture, so prefix+C-r and a restore
# agree on what is worth bringing back and there is one place to configure it.
resurrect_dir="$HOME/.tmux/plugins/tmux-resurrect"
restore_cmd=""
pane_pid="$(tmux display-message -p -t "$pane_id" '#{pane_pid}' 2>/dev/null)"
if [[ -n "$pane_pid" && -x "$resurrect_dir/save_command_strategies/ps.sh" ]]; then
  # That strategy caches `ps` output for 60s, which is fine for a timed save but
  # wrong for a keypress — bust it so we see what is running right now.
  rm -f "${TMPDIR:-/tmp}/tmux-resurrect-ps-cache" 2>/dev/null || true
  # head -1: a pipeline leaves several children, we can only relaunch one
  full_command="$("$resurrect_dir/save_command_strategies/ps.sh" "$pane_pid" 2>/dev/null | head -1)"
  if [[ -n "$full_command" ]]; then
    set +u  # the plugin's helpers are not written for nounset
    # shellcheck source=/dev/null
    . "$resurrect_dir/scripts/variables.sh"
    # shellcheck source=/dev/null
    . "$resurrect_dir/scripts/helpers.sh"
    # shellcheck source=/dev/null
    . "$resurrect_dir/scripts/process_restore_helpers.sh"
    if _process_on_the_restore_list "$full_command"; then
      restore_cmd="$(_get_inline_strategy "$full_command")"
      [[ -n "$restore_cmd" ]] || restore_cmd="$full_command"
    fi
    set -u
  fi
fi

# Env snapshot written by the precmd hook in .shell/tmux-pane-env, keyed by
# socket + pane id (pane ids are only unique per server). Handed to the new shell
# through the pane environment; that file applies it, non-destructively.
socket="$(basename "${TMUX%%,*}" 2>/dev/null)"
snapshot="${env_dir}/${socket}-${pane_id}.env"
respawn_env=()
[[ -n "$socket" && -s "$snapshot" ]] && respawn_env=(-e "TMUX_PANE_RESTORE_ENV=${snapshot}")

# --- act ---------------------------------------------------------------------
# The shell is named explicitly: with no shell-command, respawn-pane re-runs the
# command the pane was *created* with, which for e.g. `prefix+o` (ss.sh) would
# relaunch that script instead of giving us a plain shell.
if ! tmux respawn-pane -k -c "$pane_path" \
  ${respawn_env[@]+"${respawn_env[@]}"} \
  -t "$pane_id" "${SHELL:-/bin/zsh}" -l 2>/dev/null; then
  _say "respawn failed, pane left alone"
  exit 1
fi

# respawn resets the title to the default, and allow-rename/automatic-rename are
# both off, so nothing will put it back on its own.
tmux select-pane -t "$pane_id" -T "$pane_title" 2>/dev/null || true

# --- relaunch ----------------------------------------------------------------
# Typed into the fresh shell rather than exec'd, so quitting the program leaves a
# prompt behind. p10k's instant prompt buffers and replays keys, so the shell does
# not have to be fully initialised first — but give the respawn a beat regardless.
if [[ -n "$restore_cmd" ]]; then
  sleep 0.4
  tmux send-keys -t "$pane_id" "$restore_cmd" C-m 2>/dev/null || true
fi

# --- prune -------------------------------------------------------------------
# Drop snapshots for panes this socket no longer has. Cheap to do here: this runs
# on a keypress, not on a timer.
if [[ -n "$socket" && -d "$env_dir" ]]; then
  live=" $(tmux list-panes -a -F '#{pane_id}' 2>/dev/null | tr '\n' ' ')"
  for f in "$env_dir/$socket-"*.env; do
    [[ -e "$f" ]] || continue
    id="${f##*/}"; id="${id#"$socket-"}"; id="${id%.env}"
    [[ "$live" == *" $id "* ]] || rm -f "$f"
  done
fi
