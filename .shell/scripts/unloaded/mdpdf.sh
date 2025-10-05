#!/usr/bin/env bash

title="$1"
file=

if [[ -z "$title" ]]; then
  printf "PDF Title: "
  read title
fi
readonly title

file="$(echo "$title" | tr ' ' '-' | tr '[:upper:]' '[:lower:]').md"
readonly file

cat > "$file" <<EOF
---
geometry: "left=25mm,right=25mm,top=10mm,bottom=25mm"
fontsize: 12pt
mainfont: "Iosevka Term No Ligation"
documentclass: article
header-includes:
- \usepackage{fontspec}
- \setmainfont{Helvetica Neue}
- \renewcommand{\thesection}{}
- \renewcommand{\thesubsection}{\arabic{subsection}}
- \renewcommand{\thesubsubsection}{\arabic{subsection}.\arabic{subsubsection}}
---

# $title


EOF
nvim +16 "$file"
