#!/usr/bin/env bash

CLM_TARGET="${CLM_TARGET:-$HOME}"
CLM_VAULT="${CLM_VAULT:-${CLM_ROOT:-.}/vault}"

clm::die() {
  echo "clm: $*" >&2
  exit 1
}

clm::confirm() {
  local prompt="$1" reply
  if [ "${CLM_YES:-0}" = "1" ]; then
    return 0
  fi
  read -r -p "$prompt " reply
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}
