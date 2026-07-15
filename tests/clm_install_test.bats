#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
  cp "$BATS_TEST_DIRNAME/../clm-install.sh" "$CLM_ROOT/clm-install.sh"
  chmod +x "$CLM_ROOT/clm-install.sh"
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  BREW_PREFIX="$BATS_TEST_TMPDIR/brewprefix"
  mkdir -p "$FAKE_BIN" "$BREW_PREFIX/bin"
}

write_fake_brew() {
  cat > "$FAKE_BIN/brew" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "--prefix" ]; then
  echo "$BREW_PREFIX"
  exit 0
fi
if [ "\$1" = "install" ]; then
  echo "installed: \$2" >> "$BREW_PREFIX/installed.log"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/brew"
}

write_fake_stow() {
  cat > "$FAKE_BIN/stow" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$FAKE_BIN/stow"
}

@test "install links clm into the brew prefix when brew and stow are present" {
  write_fake_brew
  write_fake_stow
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  [ "$status" -eq 0 ]
  [ -L "$BREW_PREFIX/bin/clm" ]
}

@test "install runs brew install stow when stow is missing" {
  write_fake_brew
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  [ "$status" -eq 0 ]
  grep -q "installed: stow" "$BREW_PREFIX/installed.log"
}

@test "install refuses when brew is missing and not confirmed" {
  run env PATH="/usr/bin:/bin" "$CLM_ROOT/clm-install.sh" <<< "n"
  [ "$status" -ne 0 ]
}

@test "install invokes the configured install command when brew is missing and confirmed" {
  marker="$BATS_TEST_TMPDIR/marker"
  run env PATH="/usr/bin:/bin" CLM_INSTALL_BREW_INSTALL_CMD="touch '$marker'" "$CLM_ROOT/clm-install.sh" <<< "y"
  [ -e "$marker" ]
}

@test "install runs brew install gh when gh is missing" {
  write_fake_brew
  write_fake_stow
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  [ "$status" -eq 0 ]
  grep -q "installed: gh" "$BREW_PREFIX/installed.log"
}
