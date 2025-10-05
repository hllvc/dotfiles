#!/usr/bin/env bash

readonly input="$(ls *.md | fzf -1)"
readonly output="$(echo "$input" | sed 's/.md//').pdf"

pandoc --number-sections --pdf-engine=xelatex "$input" -o "$output"
quick-look "$output" 2>/dev/null || open "$output"
