#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
  mkdir -p "$CLM_ROOT/ssh/.ssh"
  cp "$BATS_TEST_DIRNAME/../ssh/.ssh/config" "$CLM_ROOT/ssh/.ssh/config"
}

@test "ssh package stows cleanly" {
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/bin/clm" stow add ssh
  [ "$status" -eq 0 ]
  [ -L "$CLM_TARGET/.ssh/config" ]
}

@test "ssh config with unmet vault includes still parses without error" {
  env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/bin/clm" stow add ssh
  run ssh -F "$CLM_TARGET/.ssh/config" -G somehost
  [ "$status" -eq 0 ]
}
