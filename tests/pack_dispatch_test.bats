#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  cat > "$FAKE_BIN/mas" <<'EOF'
#!/usr/bin/env bash
echo "12345 Some App (1.0)"
EOF
  chmod +x "$FAKE_BIN/mas"
}

@test "clm pack list works end to end" {
  run env CLM_ROOT="$CLM_ROOT" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" pack list
  [ "$status" -eq 0 ]
  [[ "$output" == *"mas [available]"* ]]
  [[ "$output" == *"brew [not present]"* ]]
}

@test "clm pack mas works end to end" {
  run env CLM_ROOT="$CLM_ROOT" CLM_PACK_DIR="$CLM_ROOT/pack" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" pack mas
  [ "$status" -eq 0 ]
  [ -e "$CLM_ROOT/pack/mas.txt" ]
}

@test "clm pack all works end to end" {
  run env CLM_ROOT="$CLM_ROOT" CLM_PACK_DIR="$CLM_ROOT/pack" CLM_BACKUP_DIR="$BATS_TEST_TMPDIR/clm-backups" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" pack all
  [ "$status" -eq 0 ]
  [[ "$output" == *"packed: mas ->"* ]]
  [[ "$output" == *"skip (not present): brew"* ]]
  [[ "$output" == *"archived: ->"* ]]
}

@test "clm pack with an unknown checker name prints usage and exits 1" {
  run env CLM_ROOT="$CLM_ROOT" PATH="/usr/bin:/bin" "$CLM_ROOT/bin/clm" pack bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: clm"* ]]
}
