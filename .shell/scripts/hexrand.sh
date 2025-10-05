#!/usr/bin/env bash

readonly DEFAULT_LENGTH=16

readonly length="${1:-$DEFAULT_LENGTH}"

openssl rand -hex "$((length / 2))" \
  | tr -d '\n' \
  | pbcopy
