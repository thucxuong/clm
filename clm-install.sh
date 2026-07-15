#!/usr/bin/env bash
set -e

CLM_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CLM_ROOT
CLM_TARGET="${CLM_TARGET:-$HOME}"
export CLM_TARGET
CLM_MACHINE_NAME="${CLM_MACHINE_NAME:-$(scutil --get ComputerName 2>/dev/null || true)}"
export CLM_MACHINE_NAME
CLM_SETTINGS_DIR="${CLM_SETTINGS_DIR:-$CLM_ROOT/cl-settings/$CLM_MACHINE_NAME}"
export CLM_SETTINGS_DIR
CLM_DOTFILES_DIR="${CLM_DOTFILES_DIR:-$CLM_SETTINGS_DIR/dotfiles}"
export CLM_DOTFILES_DIR
CLM_VAULT="${CLM_VAULT:-$CLM_SETTINGS_DIR/vault}"
export CLM_VAULT
CLM_YES="${CLM_YES:-0}"
export CLM_YES

# shellcheck source=lib/clm/common.sh
source "$CLM_ROOT/lib/clm/common.sh"

BREW_INSTALL_CMD="${CLM_INSTALL_BREW_INSTALL_CMD:-/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"}"

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    echo "Homebrew: found"
    return
  fi
  clm::confirm "Homebrew not found. Install it now?" || clm::die "Homebrew is required; aborting"
  eval "$BREW_INSTALL_CMD"
}

ensure_stow() {
  if command -v stow >/dev/null 2>&1; then
    echo "stow: found"
    return
  fi
  echo "stow not found, installing via Homebrew..."
  brew install stow
}

ensure_gh() {
  if command -v gh >/dev/null 2>&1; then
    echo "gh: found"
    return
  fi
  echo "gh not found, installing via Homebrew..."
  brew install gh
}

ensure_gh_auth() {
  if gh auth status >/dev/null 2>&1; then
    echo "gh: already authenticated"
    return
  fi
  gh auth login
}

ensure_cl_settings() {
  local repo_slug="$1"
  local cl_settings_root="$CLM_ROOT/cl-settings"
  if [ -d "$cl_settings_root" ]; then
    echo "cl-settings: found at $cl_settings_root"
    return
  fi
  if [ -z "$repo_slug" ]; then
    echo "cl-settings not found and no repo slug given — skipping auto-clone"
    return
  fi
  gh repo clone "$repo_slug" "$cl_settings_root"
}

link_clm_cli() {
  chmod +x "$CLM_ROOT/bin/clm"
  local prefix
  prefix="$(brew --prefix)"
  mkdir -p "$prefix/bin"
  ln -sf "$CLM_ROOT/bin/clm" "$prefix/bin/clm"
  echo "linked: $prefix/bin/clm -> $CLM_ROOT/bin/clm"
}

main() {
  local settings_repo="${1:-}"
  ensure_homebrew
  ensure_stow
  ensure_gh
  link_clm_cli
  ensure_gh_auth
  ensure_cl_settings "$settings_repo"
  "$CLM_ROOT/bin/clm" unpack
}

main "$@"
