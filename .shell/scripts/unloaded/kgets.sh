#!/usr/bin/env bash

objectList=
tempEnvFile="$(mktemp /tmp/$(basename $0).env.XXXXX)"

_getSecretData() { #{{{
  if [[ "$2" == noKey ]]; then
    kubectl get secret "$1" -o json \
      | jq -r '.data | to_entries[] | (.value | @base64d)'
  else
    kubectl get secret "$1" -o json \
      | jq -r '.data | to_entries[] | .key + "=" + (.value | @base64d)'
  fi
}
#}}}: _getSecretData

_getSecrets() { #{{{
  if (( ${#objectList} == 0 )); then
    return
  fi
  echo "## Secrets" >> $tempEnvFile
  for secret in ${objectList[@]}; do
    _getSecretData "$secret"
  done
  echo
}
#}}}: _getSecrets

_getConfigMaps() { #{{{
  if (( ${#objectList} == 0 )); then
    return
  fi
  echo "## Config Maps" >> $tempEnvFile
  for cm in ${objectList[@]}; do
    kubectl get cm "$cm" -o json \
      | jq -r '.data | to_entries[] | .key + "=" + .value'
  done
  echo
}
#}}}: _getConfigMaps

_getSecretsFromRef() { #{{{
  # kubectl get --no-headers deploy $1 -o json \
  #   | jq -r '.spec.template.spec.containers[]?.env[]? | select(has("valueFrom") and .valueFrom | has( "secretKeyRef" )) | .valueFrom.SecretKeyRef.name'

  kubectl get --no-headers deploy $1 -o json \
    | jq -r '.spec.template.spec.containers[]?.env[]?
      | if has("valueFrom") then .valueFrom.secretKeyRef else . end
      | if has("value") then .value else "secretRef-" + .name end'
}
#}}}: _getSecretsFromRef

_getVarNameFromRef() { #{{{
  # kubectl get --no-headers deploy $1 -o json \
  #   | jq -r '.spec.template.spec.containers[]?.env[]? | has("name") and .name'

  kubectl get --no-headers deploy $1 -o json \
    | jq -r '.spec.template.spec.containers[]?.env[]?
      | if has("name") then .name end'
}
#}}}: _getVarNameFromRef

_getSecretRefs() { #{{{
  if (( ${#objectList} == 0 )); then
    return
  fi
  secrets=()
  envNames=()
  for deploy in ${objectList[@]}; do
    # _getSecretsFromRef $deploy
    # _getVarNameFromRef $deploy
    secrets+=( $(_getSecretsFromRef $deploy) )
    envNames+=( $(_getVarNameFromRef $deploy) )
  done
  if (( ${#secrets} == 0 )); then
    return
  fi
  echo "## Deploy Secret Refs" >> $tempEnvFile
  for index in ${!envNames[@]}; do
    if [[ "${secrets[$index]}" == secretRef-* ]]; then
      echo "${envNames[$index]}=$(_getSecretData "${secrets[$index]#*-}" "noKey")" >> $tempEnvFile
    else
      echo "${envNames[$index]}=${secrets[$index]}" >> $tempEnvFile
    fi
  done
  echo
}
#}}}: _getSecretRefs

_getObjects() { #{{{
  local object="$1"
  kubectl get --no-headers "$object" | cut -f1 -d" "
}
#}}}: _getObjects

_yesNo() { #{{{
  while true; do
    read -p "Export to .env (Y/n): " res
    res=${ress:-"Y"}
    case $res in
      [Yy]*) return 0;;
      [Nn]*) return 1;;
    esac
  done
}
#}}}: _yesNo

objectList=( $(_getObjects secret | fzf --multi --exit-0) )
_getSecrets >> $tempEnvFile

objectList=( $(_getObjects cm | fzf --multi --exit-0) )
_getConfigMaps >> $tempEnvFile

objectList=( $(_getObjects deploy | fzf --multi --exit-0) )
_getSecretRefs

if (( $(cat $tempEnvFile | wc -l) == 0 )); then
  exit 0
fi

echo "$tempEnvFile"
bat $tempEnvFile

if _yesNo; then
  envFile=$(ls *.env | fzf)
  cp $tempEnvFile $envFile
fi
