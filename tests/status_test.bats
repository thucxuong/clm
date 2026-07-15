#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
  mkdir -p "$CLM_ROOT/zsh"
  echo 'x' > "$CLM_ROOT/zsh/.zshrc"
}

@test "clm status runs cleanly with no vault present" {
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_VAULT="$CLM_VAULT" "$CLM_ROOT/bin/clm" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Vault: not found"* ]]
  [[ "$output" == *"zsh [not stowed]"* ]]
}

@test "clm status reports a stowed package and vault key permission warnings" {
  env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/bin/clm" stow add zsh
  mkdir -p "$CLM_VAULT/global/ssh/keys"
  chmod 755 "$CLM_VAULT/global/ssh/keys"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_VAULT="$CLM_VAULT" "$CLM_ROOT/bin/clm" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"zsh [stowed]"* ]]
  [[ "$output" == *"WARNING"* ]]
}
