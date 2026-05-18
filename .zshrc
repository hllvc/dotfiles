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

        local output="$("$script_path" "$@")"

        if (( $? == 0 )); then
          if [[ -d "$output" ]]; then
            # echo "Chaning dir to $output."
            cd "$output"
          else
            echo "$output"
          fi
        else
          echo "Error: $output"
          return 1
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

# 1password completion (cached — forking `op` is slow)
_op_cache="${XDG_CACHE_HOME:-$HOME/.cache}/op-completion.zsh"
if [[ ! -s "$_op_cache" || "$(command -v op)" -nt "$_op_cache" ]]; then
  op completion zsh > "$_op_cache"
fi
source "$_op_cache"
compdef _op op
unset _op_cache

# load zsh completions
if type brew &>/dev/null; then
  FPATH=~/.zsh/zsh-completions:$FPATH

  # autoload -Uz compinit
  # compinit
  # autoload -Uz compaudit
  # compaudit
fi

# kubectl completions
# compdef __start_kubectl k
# source <(kubectl completion zsh)

# nvm completions (deferred — nvm is ~4700 lines)
zsh-defer -c '[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"'
zsh-defer -c '[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"'

#}}}: load completions

# 1password plugins
source /Users/hllvc/.config/op/plugins.sh

zsh-defer _load_scripts
zsh-defer _load_functions
zsh-defer source $ZSH/custom/plugins/zsh-vi-mode/zsh-vi-mode.plugin.zsh
zsh-defer source $ZSH/custom/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh

readonly configFiles=( ".shell/profile" ".shell/aliases" )

for cfgFile in "${configFiles[@]}"; do
  zsh-defer _load "$cfgFile"
done

zsh-defer _load ".shell/functions"

ZVM_VI_EDITOR=nvim
ZVM_VI_INSERT_ESCAPE_BINDKEY=jk
ZVM_READKEY_ENGINE=$ZVM_READKEY_ENGINE_ZLE
ZVM_VI_HIGHLIGHT_BACKGROUND=#3c3836
ZVM_LAZY_KEYBINDINGS=false

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

