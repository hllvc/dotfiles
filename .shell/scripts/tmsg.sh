#!/bin/bash

readonly bot_api_key="5953444652:AAHdpyPn35YEjITu3Y-Qg5_GDhLkpiJzF9E"
readonly channel="-1001668635756"
readonly msg="$(printf "%s" "$*" | jq -s -R -r @uri)"
readonly url="https://api.telegram.org/bot${bot_api_key}/sendMessage?chat_id=${channel}&text=${msg}"

curl -fSsL -X GET "$url" >/dev/null
