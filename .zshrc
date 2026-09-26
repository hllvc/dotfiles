# # Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

#{{{ private init functions
_load() { #{{{
  local file="$HOME/$1"
  if [[ ! -f "$file" ]]; then
    echo "The $file does not exist!" >&2
    return 1
  fi
  source "$file"
}
#}}}: _load

_load_functions() { #{{{
  local scripts_directory_source="${SCRIPTS_DIRECTORY:-"$HOME/.shell/scripts"}"
  local scriptsList=( "${scripts_directory_source}/functions"/*(x.) )

  if (( $#scriptsList == 0 )); then
    echo "Scripts not found in ${scripts_directory_source}/functions!"
    return 1
  fi

    for script in "${scriptsList[@]}"; do
      local script_name="$(basename "$script" .sh)"

      "$script_name"() {
        local script_directory_path="${SCRIPTS_DIRECTORY:-"$HOME/.shell/scripts"}"
        local script_file_name="$(basename "$0").sh"
        local script_path="${script_directory_path}/functions/${script_file_name}"

        # Keep declaration and assignment apart: `local x=$(...)` masks the exit code.
        local output
        output="$("$script_path" "$@")"
        local rc=$?

        if (( rc == 0 )); then
          if [[ -d "$output" ]]; then
            cd "$output"
          elif [[ -n "$output" ]]; then
            echo "$output"
          fi
        else
          [[ -n "$output" ]] && echo "Error: $output"
          return $rc
        fi
      }
    done
}
#}}}: _load_functions

_load_scripts() { #{{{
  local scripts_directory_source="${SCRIPTS_DIRECTORY:-"$HOME/.shell/scripts"}/${1:-""}"
  local scriptsList=( "$scripts_directory_source"*(x.) )

  if (( $#scriptsList == 0 )); then
    echo "Scripts not found in $scripts_directory_source!"
    return 1
  fi

  for script in "${scriptsList[@]}"; do
    local aliasName="$(basename "$script" .sh)"
    alias "$aliasName"="$script"
  done
}
#}}}: _load_scripts
#}}}: private init functions

typeset -U fpath
export ZSH_COMPDUMP="$HOME/.zcompdump"

# Completion directories have to join fpath *before* zshinit, because oh-my-zsh
# runs compinit in there. compinit scans fpath once and caches what it found in
# $ZSH_COMPDUMP, so a directory added after it is never registered — which is
# what kept both of these dead. The first line is the one `brew shellenv zsh`
# emits and the static copy below leaves out; without it none of Homebrew's
# site-functions (brew, aws, az, sg-dr, ...) are ever loaded.
# ~/.shell/completions goes first: compinit registers with `compdef -n`, so the
# first directory claiming a command wins, and these are meant to override
# (e.g. _tofu also takes over terraform from Homebrew's _terraform).
fpath=(~/.shell/completions "/opt/homebrew/share/zsh/site-functions" ~/.zsh/zsh-completions $fpath)

_load ".shell/zshinit"
_load_scripts "init/"

#{{{ load completions

# brew completions (static — avoids forking brew on every shell start)
export HOMEBREW_PREFIX="/opt/homebrew"
export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
export HOMEBREW_REPOSITORY="/opt/homebrew"
path=("/opt/homebrew/bin" "/opt/homebrew/sbin" $path)
export MANPATH="/opt/homebrew/share/man${MANPATH+:$MANPATH}:"
export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"

# Generated completions, cached: forking each tool on every shell start is slow.
# A cache is rebuilt when the watched binary is newer than it, i.e. after an
# upgrade. The generated scripts only define functions and call compdef, so
# sourcing them from inside a function is fine.
#   _cached_completion <name> <binary to watch> <generator command...>
_cached_completion() {
  local name=$1 bin=$2
  shift 2
  [[ -x $bin ]] || return 0
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/${name}-completion.zsh"
  if [[ ! -s $cache || $bin -nt $cache ]]; then
    "$@" > "$cache" 2>/dev/null || { rm -f "$cache"; return 1; }
  fi
  source "$cache"
}
_cached_completion op "$commands[op]" op completion zsh
# kubectl lives outside Homebrew, so nothing drops a _kubectl into
# site-functions. `k` completes through the alias.
_cached_completion kubectl "$commands[kubectl]" kubectl completion zsh
# /usr/local/bin/tailscale is a two-line wrapper that never changes, so watch
# the app's binary instead.
_cached_completion tailscale /Applications/Tailscale.app/Contents/MacOS/Tailscale tailscale completion zsh
unfunction _cached_completion

# zsh completion directories are set above, before zshinit runs compinit.
# After installing something that ships completions, `rm -f ~/.zcompdump*` once:
# oh-my-zsh reuses a fresh dump with `compinit -C`, which skips the scan for new
# completion functions entirely.

# gcloud completion. Homebrew's site-functions copy has no #compdef header, so
# compinit never registers it; the SDK's own script wires it up via bashcompinit.
zsh-defer -c '[ -s "/opt/homebrew/share/google-cloud-sdk/completion.zsh.inc" ] && \. "/opt/homebrew/share/google-cloud-sdk/completion.zsh.inc"'

# nvm completions (deferred — nvm is ~4700 lines)
zsh-defer -c '[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"'
zsh-defer -c '[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"'

#}}}: load completions

# 1password plugins
source "$HOME/.config/op/plugins.sh"

# Aliases, functions and shell env load eagerly — each measured at ~0ms, so
# deferring them only delayed when commands/aliases became usable (the shell felt
# "incomplete" for a beat after the prompt appeared). profile is eager so
# LANG/KEYTIMEOUT/PATH/EDITOR are set before the prompt and before gitstatusd
# spawns. Only genuinely heavy work stays deferred (nvm above; the two plugins
# below — their init re-binds ZLE widgets and is fine to land at first idle).
_load_scripts
_load_functions
_load ".shell/profile"
_load ".shell/aliases"
_load ".shell/functions"

zsh-defer source $ZSH/custom/plugins/zsh-vi-mode/zsh-vi-mode.plugin.zsh
zsh-defer source $ZSH/custom/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh

ZVM_VI_EDITOR=nvim
ZVM_VI_INSERT_ESCAPE_BINDKEY=jk
# Engine = NEX (the plugin default). NEX reads multi-key escape sequences itself
# via ZVM_ESCAPE_KEYTIMEOUT (0.03s), independent of zsh's global KEYTIMEOUT — so
# the `jk` insert-escape stays robust even though .shell/profile sets KEYTIMEOUT=1.
# The 'zle' engine instead defers to KEYTIMEOUT, which KEYTIMEOUT=1 then breaks
# (a 10ms window makes `jk` impossible / vi-mode "stops working"). That regression
# is why this is back on NEX. NEX uses pure zsh builtins — no per-keystroke fork.
ZVM_READKEY_ENGINE=nex
ZVM_VI_HIGHLIGHT_BACKGROUND=#3c3836
ZVM_LAZY_KEYBINDINGS=false
# fzf: `**<Tab>` completion plus Ctrl-T (files), Ctrl-R (history), Alt-C (cd).
# Hooked into zvm's init because zvm rebuilds the keymaps when it starts, which
# would wipe any bindings made before it.
zvm_after_init_commands+=(
  'source /opt/homebrew/opt/fzf/shell/completion.zsh'
  'source /opt/homebrew/opt/fzf/shell/key-bindings.zsh'
)

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Last on purpose: the pane-env apply only sets variables this shell left unset,
# so it has to run once everything else has configured itself.
_load ".shell/tmux-pane-env"

