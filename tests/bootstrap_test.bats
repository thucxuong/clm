#!/usr/bin/env bats

load 'test_helper'

setup() {
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  CLM_BOOTSTRAP_DIR="$BATS_TEST_TMPDIR/clm"
}

write_fake_git() {
  cat > "$FAKE_BIN/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "clone" ]; then
  echo "clone: \$2 -> \$3" >> "$BATS_TEST_TMPDIR/git-calls.log"
  mkdir -p "\$3"
  printf '#!/usr/bin/env bash\necho "clm-install.sh called with: \$1"\n' > "\$3/clm-install.sh"
  chmod +x "\$3/clm-install.sh"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/git"
}

@test "bootstrap.sh clones clm when not already present" {
  write_fake_git
  run env PATH="$FAKE_BIN:/usr/bin:/bin" CLM_BOOTSTRAP_DIR="$CLM_BOOTSTRAP_DIR" sh "$BATS_TEST_DIRNAME/../bootstrap.sh" "someone/cl-settings"
  [ "$status" -eq 0 ]
  grep -q "clone: https://github.com/thucxuong/clm.git -> $CLM_BOOTSTRAP_DIR" "$BATS_TEST_TMPDIR/git-calls.log"
}

@test "bootstrap.sh skips cloning when the target directory already exists" {
  write_fake_git
  mkdir -p "$CLM_BOOTSTRAP_DIR"
  cat > "$CLM_BOOTSTRAP_DIR/clm-install.sh" <<'EOF'
#!/usr/bin/env bash
echo "clm-install.sh called with: $1"
EOF
  chmod +x "$CLM_BOOTSTRAP_DIR/clm-install.sh"

  run env PATH="$FAKE_BIN:/usr/bin:/bin" CLM_BOOTSTRAP_DIR="$CLM_BOOTSTRAP_DIR" sh "$BATS_TEST_DIRNAME/../bootstrap.sh" "someone/cl-settings"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/git-calls.log" ]
}

@test "bootstrap.sh execs clm-install.sh with the repo slug forwarded" {
  write_fake_git
  run env PATH="$FAKE_BIN:/usr/bin:/bin" CLM_BOOTSTRAP_DIR="$CLM_BOOTSTRAP_DIR" sh "$BATS_TEST_DIRNAME/../bootstrap.sh" "someone/cl-settings"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clm-install.sh called with: someone/cl-settings"* ]]
}
