#!/usr/bin/env bash

script="$1"

if [[ -z "$script" ]]; then
  read -p "Script name: " scriptName
fi

if [[ ! "$script" == *.sh ]]; then
  script="$script.sh"
fi
readonly script

printf "#!/usr/bin/env bash\n\n" > $script
chmod +x $script
nvim +3 $script
