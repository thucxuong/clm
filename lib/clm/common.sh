#!/usr/bin/env bash

CLM_TARGET="${CLM_TARGET:-$HOME}"

clm::machine_name() {
  echo "${CLM_MACHINE_NAME:-$(scutil --get ComputerName)}"
}

CLM_MACHINE_NAME="$(clm::machine_name)"
CLM_SETTINGS_DIR="${CLM_SETTINGS_DIR:-${CLM_ROOT:-.}/cl-settings/$CLM_MACHINE_NAME}"
CLM_DOTFILES_DIR="${CLM_DOTFILES_DIR:-$CLM_SETTINGS_DIR/dotfiles}"
CLM_VAULT="${CLM_VAULT:-$CLM_SETTINGS_DIR/vault}"

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
