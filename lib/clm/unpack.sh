#!/usr/bin/env bash

clm::unpack_npm() {
  local file="$CLM_SETTINGS_DIR/pack/npm-global.txt"
  [ -f "$file" ] || { echo "no npm-global.txt found — skipping npm globals"; return 0; }
  command -v npm >/dev/null 2>&1 || { echo "npm not installed — skipping npm globals"; return 0; }
  local line name
  while IFS= read -r line; do
    case "$line" in
      *"├──"*|*"└──"*)
        name="$(echo "$line" | sed -E 's/^[^a-zA-Z0-9@]+//')"
        name="${name%@*}"
        [ -n "$name" ] || continue
        npm install -g "$name" || clm::die "npm install -g $name failed"
        echo "npm: installed $name"
        ;;
    esac
  done < "$file"
}

clm::unpack_pnpm() {
  local file="$CLM_SETTINGS_DIR/pack/pnpm-global.txt"
  [ -f "$file" ] || { echo "no pnpm-global.txt found — skipping pnpm globals"; return 0; }
  command -v pnpm >/dev/null 2>&1 || { echo "pnpm not installed — skipping pnpm globals"; return 0; }
  local line name in_deps=0
  while IFS= read -r line; do
    if [ "$line" = "dependencies:" ]; then
      in_deps=1
      continue
    fi
    [ "$in_deps" = "1" ] || continue
    [ -n "$line" ] || continue
    name="${line%% *}"
    [ -n "$name" ] || continue
    pnpm add -g "$name" || clm::die "pnpm add -g $name failed"
    echo "pnpm: installed $name"
  done < "$file"
}

cmd_unpack() {
  [ -d "$CLM_SETTINGS_DIR" ] || clm::die "cl-settings not found at $CLM_SETTINGS_DIR (clone it first: gh repo clone <you>/cl-settings $CLM_SETTINGS_DIR)"
  cmd_stow_onboard
  cmd_vault_fix_perms
  if [ -f "$CLM_SETTINGS_DIR/pack/Brewfile" ]; then
    brew bundle --file="$CLM_SETTINGS_DIR/pack/Brewfile" || clm::die "brew bundle failed"
    echo "brew bundle complete"
  else
    echo "no Brewfile found at $CLM_SETTINGS_DIR/pack/Brewfile — skipping CLI tools/apps install"
  fi
  clm::unpack_npm
  clm::unpack_pnpm
}
