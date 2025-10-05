#!/usr/bin/env bash

#{{{ Print colors
declare -A COLOR=(
  [red_bold]="\033[1;31m"
  [red]="\033[0;31m"
  [green_bold]="\033[1;32m"
  [green]="\033[0;32m"
  [yellow_bold]="\033[1;33m"
  [yellow]="\033[0;33m"
  [blue_bold]="\033[1;34m"
  [blue]="\033[0;34m"
  [magenta_bold]="\033[1;35m"
  [magenta]="\033[0;35m"
  [cyan_bold]="\033[1;36m"
  [cyan]="\033[0;36m"
  [reset]="\033[0m"
  [bold]="\033[1m"
)
#}}}: Pretty Print Colors

_clear_line() { #{{{
  printf "\r\033[2K"
}
#}}}: _clear_line

_error() { #{{{
  local -r message="$1"
  printf "${COLOR[red_bold]}::${COLOR[reset]} %s\n" "$message"
  exit 1
}
#}}}: _error

_in_progress() { #{{{
  local message="$1"
  local command="$2"

  eval "$command" &
  local pid=$!

  local dots=1
  local increasing=true

  while kill -0 $pid 2>/dev/null; do
    _clear_line
    printf "${COLOR[blue_bold]}::${COLOR[reset]} %s%*s" "$message" "$dots" | tr ' ' '.'

    if ((increasing)); then
      ((dots++))
      if ((dots > 3)); then
        increasing=false
        ((dots--))
      fi
    else
      ((dots--))
      if ((dots < 1)); then
        increasing=true
        ((dots++))
      fi
    fi

    sleep 0.3
  done

  wait $pid
  local exit_code=$?

  _clear_line

  return $exit_code
}
#}}}: _in_progress

_info() { #{{{
  local -r message="$1"
  printf "${COLOR[green_bold]}::${COLOR[reset]} %s\n" "$message"
}
#}}}: _info

_fetch_configurations() { #{{{
  local -n output=$1
  sleep 5
  output="$(gcloud config configurations list --format='list')"
  sleep 5
}
#}}}: _fetch_configurations

_in_progress "Test" "sleep 5"
exit 0

# Fetching raw gcloud configurations
# readonly configurations_raw="$(gcloud config configurations list --format='list')"
_fetch_configurations raw_conf &
_in_progress "Fetching configurations"
_clear_line && _info "Got the configurations."
exit 0

## Using yq to parse the output, it's faster than using gcloud with --filter
# echo "Fetching active configuration..."
# readonly active_configuration="$(echo "$configurations_raw" | yq '.[] | select(.is_active == True)')"
# readonly active_configuration="$(gcloud config configurations list --filter='is_active=true' --format='list')"

# echo "Formating confugurations..."
# _info "Formating confugurations..."
# readonly configurations="$(echo "$configurations_raw")"

## I need to parse output from yaml directly and attach color codes
## It cannot be saved to yaml first and then used cuz it currupts color codes
## So, get $configurations_raw, parse through yq to attach colors to is_active == True and output
## Every other item should have default .name (color)
echo "$configurations_raw" |
  yq ".[] | select(.is_active == True) | \"${COLOR[bold]}\" + .name + \"${COLOR[reset]}\"" |
  xargs printf
exit 0

# printf ":: Configurations:\n%s\n" "$configurations"
readonly configurations_names="$(echo "$configurations" | yq '.[].name')"
printf ":: Configurations names:\n%s\n" "$configurations_names"

# printf ":: Active configuration:\n%s\n" "$active_configuration"
readonly active_configuration_name="$(echo "$active_configuration" | yq '.name')"
printf ":: Active configuration name:\n%s\n" "$active_configuration_name"

printf "$configurations_names" | fzf --ansi
# printf "%s\n${COLOR[bold]}%s" "$configurations_names" "$active_configuration_name" | fzf --ansi
