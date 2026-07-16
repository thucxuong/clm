#!/usr/bin/env bash
set -e

VAULT_ROOT="${1:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

fix_keys_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  chmod 700 "$dir"
  local f
  for f in "$dir"/*; do
    [ -e "$f" ] || continue
    [ -f "$f" ] && chmod 600 "$f"
  done
}

fix_keys_dir "$VAULT_ROOT/global/ssh/keys"

for proj in "$VAULT_ROOT"/projects/*/; do
  [ -d "$proj" ] || continue
  fix_keys_dir "${proj}ssh/keys"
done

echo "vault key permissions fixed"
