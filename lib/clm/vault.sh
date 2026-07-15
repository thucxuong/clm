#!/usr/bin/env bash

cmd_vault_fix_perms() {
  [ -d "$CLM_VAULT" ] || clm::die "vault not found at $CLM_VAULT (clone it first: git clone <vault-repo-url> $CLM_VAULT)"
  local script="$CLM_VAULT/bin/fix-perms.sh"
  [ -x "$script" ] || clm::die "missing or non-executable: $script"
  "$script" "$CLM_VAULT"
}
