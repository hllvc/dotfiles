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
    echo "The $file does not exist!"
    return
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

_load ".shell/zshinit"
_load_scripts "init/"

#{{{ load completions

# brew completions
eval "$(/opt/homebrew/bin/brew shellenv)"

# 1password completion
eval "$(op completion zsh)"; compdef _op op

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

readonly configFiles=( ".shell/profile" ".shell/aliases" )

for cfgFile in "${configFiles[@]}"; do
  zsh-defer _load "$cfgFile"
done

_load ".shell/functions"

ZVM_VI_EDITOR=nvim
ZVM_VI_INSERT_ESCAPE_BINDKEY=jk
ZVM_READKEY_ENGINE=$ZVM_READKEY_ENGINE_NEX
ZVM_VI_HIGHLIGHT_BACKGROUND=#3c3836
ZVM_LAZY_KEYBINDINGS=false

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

autoload -Uz compinit
if [ "$(date +'%j')" != "$(stat -f '%Sm' -t '%j' ~/.zcompdump 2>/dev/null)" ]; then
    compinit
else
    compinit -C
fi
