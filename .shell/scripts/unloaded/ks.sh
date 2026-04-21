#!/usr/bin/env bash
#
# The script for extracting secrets from Kubernetes Secret.

_list_secrets() { #{{{
  local custom_output="NAME:.metadata.name,TYPE:.type"
  local field_selector="--field-selector="
  local excluded_secrets=(
    "helm.sh/release.v1"
  )

  for pattern in "${excluded_secrets[@]}"; do
    field_selector+="type!=$pattern,"
  done

  kubectl get secrets \
    --server-print=false \
    --output=custom-columns=$custom_output \
    $field_selector
}
#}}}: _list_secrets

_pretty_fzf() { #{{{
  local header_lines="${1:-1}"
  local input_label="${2:-"$(kubectl config current-context) ($(kubectl ns -c)) "}"
  local preview="${3:-"kubectl describe secret {+1}"}"
  cat | fzf -m \
    --header-lines=$header_lines \
    --header-border \
    --layout=reverse \
    --input-label="$input_label" \
    --no-separator \
    --style=full \
    --preview="$preview"
}
#}}}: _pretty_fzf

_get_names() { #{{{
  cat | cut -f1 -d ' '
}
#}}}: _get_names

_get_json_secret() { #{{{
  local secret="$1"
  kubectl get secrets "$secret" -o json | jq -c
}
#}}}: _get_json_secret

_secret_keys() { #{{{
  cat | jq -r '.data | keys[]' | tr ' ' '\n'
}
#}}}: _secret_keys

_export_selected() { #{{{
  local secret="$1"
  local secret_value="$2"
  local key_preview="echo '$secret_value' | yq | jq -r --arg key {} '.data.[\$key] | @base64d'"

  echo "$secret_value" | _secret_keys | _pretty_fzf 0 "$secret" "$key_preview"
}
#}}}: _export_selected

_get_value_for_key() { #{{{
  local key="$1"
  cat | jq -r ".data.\"$key\" | @base64d"
}
#}}}: _get_value_for_key

_decode_value() { #{{{
  local secret_value="$1"
  local -n input="$2"
  local output=""

  for key in "${input[@]}"; do
    output+="$key='$(echo "$secret_value" | _get_value_for_key "$key")'\n"
  done

  printf "$output"
}
#}}}: _decode_value

_process_secret() { #{{{
  local secret="$1"
  local secret_value="$(_get_json_secret "$secret")"
  local selected_keys=( $(_export_selected "$secret" "$secret_value") )

  _decode_value "$secret_value" selected_keys
}
#}}}: _process_secret

_format_output() { #{{{
  local output=( $(cat) )
  local outputCount="${#output[@]}"

  for ((i=0; i<$outputCount; i++)); do
    if ((i<outputCount-1)); then
      echo "${output[$i]}"
      continue
    fi
    echo "${output[$i]}" | tr -d '\n'
  done
}
#}}}: _format_output

main() {
  readonly local selected_secrets=( $(_list_secrets | _pretty_fzf | _get_names) )

  for secret in "${selected_secrets[@]}"; do
    # _process_secret "$secret" | _format_output | pbcopy
    _process_secret "$secret" | pbcopy
  done
}

main "$@"
