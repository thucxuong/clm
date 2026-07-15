#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
}

@test "die prints a prefixed message to stderr and exits 1" {
  run bash -c "source '$CLM_ROOT/lib/clm/common.sh'; clm::die 'boom'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"clm: boom"* ]]
}

@test "confirm bypasses the prompt when CLM_YES=1" {
  run bash -c "export CLM_YES=1; source '$CLM_ROOT/lib/clm/common.sh'; clm::confirm 'proceed?'"
  [ "$status" -eq 0 ]
}

@test "confirm returns success on a piped y" {
  run bash -c "source '$CLM_ROOT/lib/clm/common.sh'; echo y | clm::confirm 'proceed?'"
  [ "$status" -eq 0 ]
}

@test "confirm returns failure on a piped n" {
  run bash -c "source '$CLM_ROOT/lib/clm/common.sh'; echo n | clm::confirm 'proceed?'"
  [ "$status" -eq 1 ]
}

@test "confirm returns failure on empty input" {
  run bash -c "source '$CLM_ROOT/lib/clm/common.sh'; echo '' | clm::confirm 'proceed?'"
  [ "$status" -eq 1 ]
}

@test "machine_name respects CLM_MACHINE_NAME override" {
  run bash -c "
    export CLM_MACHINE_NAME='test-machine'
    source '$CLM_ROOT/lib/clm/common.sh'
    clm::machine_name
  "
  [ "$status" -eq 0 ]
  [ "$output" = "test-machine" ]
}

@test "sourcing common.sh does not crash when scutil is unreachable on PATH" {
  run bash -c "
    unset CLM_MACHINE_NAME
    export PATH='/usr/bin:/bin'
    source '$CLM_ROOT/lib/clm/common.sh'
    echo ok
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "CLM_SETTINGS_DIR, CLM_DOTFILES_DIR, and CLM_VAULT default from CLM_ROOT and machine name" {
  run bash -c "
    unset CLM_VAULT CLM_DOTFILES_DIR CLM_SETTINGS_DIR
    export CLM_ROOT='/tmp/fake-clm-root'
    export CLM_MACHINE_NAME='test-machine'
    source '$CLM_ROOT/lib/clm/common.sh'
    echo \"\$CLM_SETTINGS_DIR\"
    echo \"\$CLM_DOTFILES_DIR\"
    echo \"\$CLM_VAULT\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/fake-clm-root/cl-settings/test-machine"* ]]
  [[ "$output" == *"/tmp/fake-clm-root/cl-settings/test-machine/dotfiles"* ]]
  [[ "$output" == *"/tmp/fake-clm-root/cl-settings/test-machine/vault"* ]]
}

@test "explicit CLM_SETTINGS_DIR override takes precedence over the computed default" {
  run bash -c "
    unset CLM_VAULT CLM_DOTFILES_DIR CLM_SETTINGS_DIR
    export CLM_ROOT='/tmp/fake-clm-root'
    export CLM_MACHINE_NAME='test-machine'
    export CLM_SETTINGS_DIR='/tmp/custom-settings'
    source '$CLM_ROOT/lib/clm/common.sh'
    echo \"\$CLM_DOTFILES_DIR\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/custom-settings/dotfiles" ]
}
