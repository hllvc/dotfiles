#!/bin/bash

readonly bot_api_key=""
readonly channel=""

[[ -z "$bot_api_key" ]] && exit 0

readonly msg="$(printf "%s" "$*" | jq -s -R -r @uri)"
readonly url="https://api.telegram.org/bot${bot_api_key}/sendMessage?chat_id=${channel}&text=${msg}"

curl -fSsL -X GET "$url" >/dev/null
