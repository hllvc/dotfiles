#!/usr/bin/env bash

scriptName="$1"

if [[ -z "$scriptName" ]]; then
  read -rp "Script name: " scriptName
fi

if [[ ! "$scriptName" == *.sh ]]; then
  scriptName="$scriptName.sh"
fi
readonly scriptName

printf "#!/usr/bin/env bash\n\n" > "$scriptName"
chmod +x "$scriptName"
nvim +3 "$scriptName"
