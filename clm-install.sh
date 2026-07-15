#!/usr/bin/env bash
set -e

CLM_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CLM_ROOT
CLM_TARGET="${CLM_TARGET:-$HOME}"
export CLM_TARGET
CLM_VAULT="${CLM_VAULT:-$CLM_ROOT/vault}"
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

link_clm_cli() {
  chmod +x "$CLM_ROOT/bin/clm"
  local prefix
  prefix="$(brew --prefix)"
  mkdir -p "$prefix/bin"
  ln -sf "$CLM_ROOT/bin/clm" "$prefix/bin/clm"
  echo "linked: $prefix/bin/clm -> $CLM_ROOT/bin/clm"
}

main() {
  ensure_homebrew
  ensure_stow
  link_clm_cli
  cat <<EOF

Done. 'clm' is now on your PATH.

Next steps:
  clm stow onboard
  git clone <vault-repo-url> $CLM_VAULT
  clm vault fix-perms
EOF
}

main "$@"
