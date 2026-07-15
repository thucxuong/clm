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
