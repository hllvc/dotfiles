#!/usr/bin/env bash

export JIRA_API_TOKEN="$(op read "op://Bloomteq General/Jira API Key/credential")"

_loader() { #{{{
  local msg="$1"
  local delay=0.2
  while true; do
    printf "\r${C_YELLOW}:${C_RESET}  ${C_BOLD}%s${C_RESET}" "$msg"
    sleep $delay
    printf "\r${C_YELLOW_BOLD}:${C_RESET}  ${C_BOLD}%s${C_RESET}" "$msg"
    sleep $delay
    printf "\r${C_YELLOW}:${C_YELLOW}:${C_RESET} ${C_BOLD}%s${C_RESET}" "$msg"
    sleep $delay
    printf "\r${C_YELLOW}:${C_YELLOW_BOLD}:${C_RESET} ${C_BOLD}%s${C_RESET}" "$msg"
    sleep $delay
    printf "\r ${C_YELLOW_BOLD}:${C_RESET} ${C_BOLD}%s${C_RESET}" "$msg"
    sleep $delay
    printf "\r ${C_YELLOW}:${C_RESET} ${C_BOLD}%s${C_RESET}" "$msg"
    sleep $delay
    printf "\r   ${C_BOLD}%s${C_RESET}" "$msg"
    sleep $delay
  done
}
#}}}: _loader

_progress_bar() { #{{{
  local current=$1
  local total=$2
  local title=$3
  local percent=$((current * 100 / total))
  local completed_message="Completed"
  local bar_l=${#completed_message}
  local filled_l=$((bar_l * current / total))
  local empty_l=$((bar_l - filled_l))

  # Create the progress bar
  local bar=$(printf "%-${filled_l}s" "#" | tr ' ' '#')
  if ((filled_l == 0)); then
    bar=""
  fi
  local empty=$(printf "%-${empty_l}s" " ")

  # Print the progress bar
  if ((percent == 100)); then
    printf "\r${C_GREEN_BOLD}::${C_RESET} $title [${C_GREEN}Completed${C_RESET}]     "
  else
    printf "\r${C_YELLOW_BOLD}::${C_RESET}${C_BOLD} $title [${bar}${empty}] %3d%%${C_RESET}" "$percent"
  fi
}
#}}}: _progress_bar

#_cleanup() { #{{{
#  kill $loader_pid 2>/dev/null
#  wait $loader_pid 2>/dev/null
#  printf "\r${C_RED_BOLD}::${C_RESET} Cleaning up.."
#}
##}}}: _clenaup

#trap _cleanup EXIT

readonly date="$(date -v-3m +%Y-%m)"
readonly grep_regex="${date}-[0-9]{2}"

printf ":: Fetching sprints in month: $date\r"
readonly sprint_ids=( $(jira sprint list \
  -p BDO \
  --plain \
  --no-headers \
  --columns=ID,NAME,START,END \
  | grep -E "$grep_regex" | cut -f1) )

printf ":: Found ${#sprint_ids[@]} sprints in month: $date.  "
echo

issue_ids=()
counter=0
_loader "Fetching sprint issues" &
loader_pid=$!
for id in "${sprint_ids[@]}"; do
  # ((counter++))
  # _progress_bar \
  #   "$counter" \
  #   "${#sprint_ids[@]}" \
  #   "Fetching sprint issues"
  # echo ":: Fetching issues in sprint: $id.."
  issue_ids+=( $(jira sprint list "$id" \
    --plain \
    --no-headers \
    --columns ID) )
done
readonly issue_ids
kill $loader_pid
wait $loader_pid 2>/dev/null
printf "\r${C_GREEN_BOLD}::${C_RESET} ${C_GREEN}Fetching sprint issues${C_RESET}          "
# echo ">> Found ${#issue_ids[@]} in all sprints."
echo

seconds=()
counter=0
_loader "Fetching worklog across sprint issues" &
loader_pid=$!
for id in "${issue_ids[@]}"; do
  # ((counter++))
  # _progress_bar \
  #   "$counter" \
  #   "${#issue_ids[@]}" \
  #   "Fetching worklog across sprint issues"
  # echo ":: Fetching time for issue: $id.."
  seconds+=( $(jira issue view "$id" --raw \
    | jq -r --arg date "$date" '[.fields.worklog.worklogs[] | select(.created | startswith($date))] | .[].timeSpentSeconds') )
done
readonly seconds
kill $loader_pid
wait $loader_pid 2>/dev/null
printf "\r${C_GREEN_BOLD}::${C_RESET} ${C_GREEN}Fetching worklog across sprint issues${C_RESET}         "
# echo ">> Found ${#seconds[@]} time log entries."
echo

seconds_sum=0
for seconds_count in "${seconds[@]}"; do
  seconds_sum=$(( seconds_sum + seconds_count ))
done
readonly seconds_sum

readonly hours=$(( seconds_sum/3600 ))
remaining_s=$(( seconds_sum%3600 ))

readonly minutes=$(( remaining_s/60 ))
remaining_s=$(( remaining_s%60 ))
readonly remaining_s

echo
echo "Total seconds: $seconds_sum"
echo "Total time: ${hours}h, ${minutes}m, ${remaining_s}s"
