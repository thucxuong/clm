#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
}

@test "clm vault fix-perms refuses when vault has not been cloned" {
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_VAULT="$CLM_VAULT" "$CLM_ROOT/bin/clm" vault fix-perms
  [ "$status" -ne 0 ]
  [[ "$output" == *"vault not found"* ]]
}

@test "clm vault fix-perms runs the vault's own fix-perms.sh" {
  mkdir -p "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  cp "$BATS_TEST_DIRNAME/../vault/bin/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  echo fake > "$CLM_VAULT/global/ssh/keys/id_ed25519"
  chmod 644 "$CLM_VAULT/global/ssh/keys/id_ed25519"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_VAULT="$CLM_VAULT" "$CLM_ROOT/bin/clm" vault fix-perms
  [ "$status" -eq 0 ]
  [ "$(stat -f '%Lp' "$CLM_VAULT/global/ssh/keys/id_ed25519")" = "600" ]
}
