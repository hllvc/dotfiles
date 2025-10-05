#!/usr/bin/env bash

set -eo pipefail

readonly kube_ctx=$(kubectl config get-contexts --no-headers=true -o "name" \
  | fzf --preview 'kubectl get ns --context {} --no-headers | cut -f1 -d" "')

if [[ -n $kube_ctx ]]; then
  kubectx "$kube_ctx" &>/dev/null &
else
  exit 0
fi

readonly kube_ctx_ns=$(kubectl get ns --context "$kube_ctx" --no-headers | awk '{print $1}' \
  | fzf --preview 'kubectl get po -n {}')

if [[ -n $kube_ctx_ns ]]; then
  kubens "$kube_ctx_ns" &>/dev/null &
else
  exit 0
fi

if [[ "$1" == "ro" ]]; then
  k9s --context "$kube_ctx" -n "$kube_ctx_ns" --readonly
else
  k9s --context "$kube_ctx" -n "$kube_ctx_ns"
fi
