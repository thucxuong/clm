#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
}

@test "pack_available detects presence via PATH and absence otherwise" {
  cat > "$FAKE_BIN/brew" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$FAKE_BIN/brew"

  run bash -c "
    export CLM_ROOT='$CLM_ROOT'
    export PATH='$FAKE_BIN:/usr/bin:/bin'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/pack.sh'
    clm::pack_available brew
  "
  [ "$status" -eq 0 ]

  run bash -c "
    export CLM_ROOT='$CLM_ROOT'
    export PATH='/usr/bin:/bin'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/pack.sh'
    clm::pack_available brew
  "
  [ "$status" -eq 1 ]
}

@test "cmd_pack_list reports available and not-present checkers" {
  cat > "$FAKE_BIN/brew" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$FAKE_BIN/brew"

  run bash -c "
    export CLM_ROOT='$CLM_ROOT'
    export PATH='$FAKE_BIN:/usr/bin:/bin'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/pack.sh'
    cmd_pack_list
  "
  [[ "$output" == *"brew [available]"* ]]
  [[ "$output" == *"mas [not present]"* ]]
}

@test "cmd_pack_one skips a checker whose tool isn't present" {
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_PACK_DIR='$CLM_ROOT/pack'
    export PATH='/usr/bin:/bin'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/pack.sh'
    cmd_pack_one mas
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip (not present): mas"* ]]
  [ ! -e "$CLM_ROOT/pack/mas.txt" ]
}

@test "cmd_pack_one runs an available checker and writes its output file" {
  cat > "$FAKE_BIN/mas" <<'EOF'
#!/usr/bin/env bash
echo "12345 Some App (1.0)"
EOF
  chmod +x "$FAKE_BIN/mas"

  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_PACK_DIR='$CLM_ROOT/pack'
    export PATH='$FAKE_BIN:/usr/bin:/bin'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/pack.sh'
    cmd_pack_one mas
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"packed: mas -> $CLM_ROOT/pack/mas.txt"* ]]
  grep -q "Some App" "$CLM_ROOT/pack/mas.txt"
}

@test "cmd_pack_one dies on an unknown checker name" {
  run bash -c "
    export CLM_ROOT='$CLM_ROOT'
    export PATH='/usr/bin:/bin'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/pack.sh'
    cmd_pack_one bogus
  "
  [ "$status" -ne 0 ]
}

@test "cmd_pack_all runs every checker, packing available ones and skipping the rest" {
  cat > "$FAKE_BIN/npm" <<'EOF'
#!/usr/bin/env bash
printf '/fake/lib\n+-- pnpm@1.0.0\n'
EOF
  chmod +x "$FAKE_BIN/npm"

  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_PACK_DIR='$CLM_ROOT/pack'
    export PATH='$FAKE_BIN:/usr/bin:/bin'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/pack.sh'
    cmd_pack_all
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"packed: npm ->"* ]]
  [[ "$output" == *"skip (not present): brew"* ]]
  [ -e "$CLM_ROOT/pack/npm-global.txt" ]
}
