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
  local scriptsList=( "${scripts_directory_source}/functions"/*(x) )

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
  local scripts_directory_source="${SCRIPTS_DIRECTORY:-"$HOME/.shell/scripts/${1:-""}"}"
  local scriptsList=( "$scripts_directory_source"*(x) )

  if (( $#scriptsList == 0 )); then
    echo "Scripts not found in $scripts_directory_source!"
    return 1
  fi

  for script in "${scriptsList[@]}"; do
    local aliasName="$(basename "$script" .sh)"
    alias "$aliasName"="$script \$@"
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

# nvm completions
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

#}}}: load completions

# 1password plugins
source /Users/hllvc/.config/op/plugins.sh

zsh-defer _load_scripts
zsh-defer _load_functions

readonly configFiles=( ".shell/profile" ".shell/aliases" )

for cfgFile in "${configFiles[@]}"; do
  zsh-defer _load "$cfgFile"
done

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# prcalrt() {
#   br_tag=$(git branch --show-current)
#   # terminal-notifier -title "All checks are done!" -message "PR Checks on branch $br_tag are finished."
#   tmsg "PR Checks on branch $br_tag are finished."
# }

# alrt() {
#   terminal-notifier -title "Command execution finished" -message "$*"
# }

# azss() {
#   local subscription=$( \
#     cat config.sh \
#     | grep "subscription=" -m1 \
#     | cut -d'=' -f2 \
#     | tr -d '"' \
#   )
#   az account set --subscription "${subscription}"
# }

cpg() {
  if [ -d "$2" ];then
    cp $1 $2 && cd $2
  else
    cp $1 $2
  fi
}

mvg() {
  if [ -d "$2" ];then
    mv $1 $2 && cd $2
  else
    mv $1 $2
  fi
}

take() {
  mkdir -p $1
  cd $1
}

bup() {
  if [[ -d $1 ]]; then
    sudo cp -r $1 $1.old
  else
    sudo cp $1 $1.old
  fi
  echo "delete original (Y/n): "
  read choice
  [[ $choice == "" ]] && choice="y"
  if [[ $choice == "y" ]] || [[ $choice == "Y" ]]; then
    echo "Deleted:"
    if [[ -d $1 ]]; then
      sudo rm -rfv $1
    else
      sudo rm -fv $1
    fi
  fi
}

res() {
  arr=( $(awk '{last=split($0, a, "."); for (i in a) if ( i != last ) print i"%"a[i]}' <<< $1 | sort | sed 's/[0-9]%//') )
  newname=$(echo $arr | sed 's/ /./g')
  if [[ -d $1 ]]; then
    echo "Deleted:"
    sudo cp -r $1 $newname
  else
    sudo cp $1 $newname
  fi
  echo "delete original (Y/n): "
  read choice
  [[ $choice == "" ]] && choice="y"
  if [[ $choice == "y" ]] || [[ $choice == "Y" ]]; then
    if [[ -d $1 ]]; then
      sudo rm -rfv $1
    else
      sudo rm -fv $1
    fi
  fi
}

vi() {
  echo $PWD > ~/.curr
  if [[ -d "$1" ]]; then
    cd "$1"; nvim +':CocCommand explorer'
    # ranger "$1"
  else
    nvim "$@"
  fi
}

copy() {
  mkdir /tmp/copy
  for item in $@; do
    if [[ -d $item ]]; then
      cp -rv $item /tmp/copy/
    else
      cp -v $item /tmp/copy
    fi
  done
}

cpaste() {
  if [[ -z $@ ]]; then
    mv -v /tmp/copy/.* .
    mv -v /tmp/copy/* .
  else
    if [[ $# > 1 ]]; then
      for dest in $@; do
        cp -rv /tmp/copy/* $dest
        cp -rv /tmp/copy/.* $dest
      done
    else
      cp -rv /tmp/copy/.* $1
      cp -rv /tmp/copy/* $1
    fi
  fi
}

cclean() {
  rm -rfv /tmp/copy/*
}

lscopy() {
  if [[ -e /tmp/copy ]]; then
    echo "items:"
    ls -lAtG /tmp/copy
    echo "---"
    tree /tmp/copy
  else
    echo "Nothing copied!"
  fi
}

#export NVIMRC="$HOME/.config/nvim/init.vim"

ZVM_VI_EDITOR=nvim
ZVM_VI_INSERT_ESCAPE_BINDKEY=jk
ZVM_READKEY_ENGINE=$ZVM_READKEY_ENGINE_NEX
ZVM_VI_HIGHLIGHT_BACKGROUND=#3c3836
ZVM_LAZY_KEYBINDINGS=false
#export KEYTIMEOUT=1

bundle_id() {
  app_name="$(ls /Applications |\
    sed 's/.app.*//' |\
    sed 's/Utilities\///' |\
    sort -r |\
    fzf)"

  osascript -e "id of app \"$app_name\"" |\
    tr -d '\n' | pbcopy
}

# get .crx for chrome extension in Arc
# getcrx() {
#   local input="$1"
#   local s_query=

#   if [[ -z "$input" ]]; then
#     printf "Search for extension and start download!\n"
#     printf "\e[sSearch query: ${C_BOLD}"
#     read -r s_query
#     printf "\e[u\e[2K\e[1A\e[2K\e[s${C_RESET}"
#   else
#     s_query="$input"
#   fi

#   search_url="https://chrome.google.com/webstore/search/${s_query}"
#   open -a Arc "$search_url"

#   local readonly workingDir="$(pwd)"

#   local crx_name="${s_query/ /_}"
#   local crx_download_dir="$HOME/Library/Application Support/Arc/User Data/Webstore Downloads"
#   local crx_temp_dir="${crx_name}_crx"

#   cd "$crx_download_dir"
#   mkdir "$crx_temp_dir"

#   local started=false
#   local copy_in_progress=false
#   while [[ -f *.crx ]] || ! $started; do
#     command cp *.crx "${crx_temp_dir}/${crx_name}.crx" 2>/dev/null \
#       && copy_in_progress=true
#     if (($?==1)) && $copy_in_progress; then
#       started=true
#     elif ! $copy_in_progress; then
#       printf "\e[sWaiting for download to start..\r"
#     else
#       printf "\e[2KFile found. Copying..\r"
#     fi
#   done 2>/dev/null

#   open -a Arc "arc://extensions"
#   sleep 1
#   cd "$crx_temp_dir"; ofd
#   cd "$workingDir"

#   printf "\e[2KPress ${C_BOLD}ENTER${C_RESET} to clean.. \e[s"
#   read
#   command rm -rf "${crx_download_dir}/${crx_temp_dir}"
#   printf "\e[uRemoved [${C_BOLD}${crx_temp_dir}/${crx_name}.crx${C_RESET}]"
# }

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

### jenv
# eval "$(jenv init -)"

# zstyle ':completion:*' menu select
fpath+=~/.zfunc

# The following lines have been added by Docker Desktop to enable Docker CLI completions.
fpath=(/Users/hllvc/.docker/completions $fpath)
# autoload -Uz compinit
# compinit
# End of Docker CLI completions

autoload -Uz compinit
if [ "$(date +'%j')" != "$(stat -f '%Sm' -t '%j' ~/.zcompdump 2>/dev/null)" ]; then
    compinit
else
    compinit -C
fi

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/hllvc/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/hllvc/Downloads/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/hllvc/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/hllvc/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

export PATH="$PATH:$HOME/.local/bin"
