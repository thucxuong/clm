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
if [ "\$1" = "bundle" ]; then
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

write_real_stow() {
  ln -sf "$(command -v stow)" "$FAKE_BIN/stow"
}

@test "install makes bin/clm executable without touching the brew prefix" {
  write_fake_brew
  write_fake_stow
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  [ -x "$CLM_ROOT/bin/clm" ]
  [ ! -e "$BREW_PREFIX/bin/clm" ]
}

@test "install runs brew install stow when stow is missing" {
  write_fake_brew
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
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
  grep -q "installed: gh" "$BREW_PREFIX/installed.log"
}

write_fake_gh() {
  local auth_status_exit="$1"
  cat > "$FAKE_BIN/gh" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "auth" ] && [ "\$2" = "status" ]; then
  exit $auth_status_exit
fi
if [ "\$1" = "auth" ] && [ "\$2" = "login" ]; then
  echo "login called" >> "$BREW_PREFIX/gh-login.log"
  exit 0
fi
if [ "\$1" = "repo" ] && [ "\$2" = "clone" ]; then
  echo "clone called: \$3 -> \$4" >> "$BREW_PREFIX/gh-clone.log"
  mkdir -p "\$4"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/gh"
}

@test "ensure_gh_auth skips gh auth login when already authenticated" {
  write_fake_brew
  write_fake_stow
  write_fake_gh 0
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  [ ! -e "$BREW_PREFIX/gh-login.log" ]
}

@test "ensure_gh_auth invokes gh auth login when not authenticated" {
  write_fake_brew
  write_fake_stow
  write_fake_gh 1
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  grep -q "login called" "$BREW_PREFIX/gh-login.log"
}

@test "ensure_cl_settings skips cloning when cl-settings already exists" {
  write_fake_brew
  write_fake_stow
  write_fake_gh 0
  mkdir -p "$CLM_ROOT/cl-settings"
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh" "someone/cl-settings"
  [ ! -e "$BREW_PREFIX/gh-clone.log" ]
}

@test "ensure_cl_settings clones when given a repo slug and cl-settings doesn't exist" {
  write_fake_brew
  write_fake_stow
  write_fake_gh 0
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh" "someone/cl-settings"
  grep -q "clone called: someone/cl-settings ->.*/cl-settings$" "$BREW_PREFIX/gh-clone.log"
}

@test "ensure_cl_settings skips gracefully with a helpful message when no slug is given" {
  write_fake_brew
  write_fake_stow
  write_fake_gh 0
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  [ ! -e "$BREW_PREFIX/gh-clone.log" ]
  [[ "$output" == *"skipping auto-clone"* ]]
}

@test "full bootstrap: install, auth, clone, and unpack succeed in one go" {
  write_fake_brew
  write_real_stow
  FAKE_UPSTREAM="$BATS_TEST_TMPDIR/fake-upstream/test-machine"
  mkdir -p "$FAKE_UPSTREAM/dotfiles/zsh" "$FAKE_UPSTREAM/vault/global/ssh/keys" "$FAKE_UPSTREAM/vault/bin" "$FAKE_UPSTREAM/pack"
  echo 'export FOO=1' > "$FAKE_UPSTREAM/dotfiles/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/../lib/clm/templates/fix-perms.sh" "$FAKE_UPSTREAM/vault/bin/fix-perms.sh"
  chmod +x "$FAKE_UPSTREAM/vault/bin/fix-perms.sh"
  echo '# empty brewfile' > "$FAKE_UPSTREAM/pack/Brewfile"

  cat > "$FAKE_BIN/gh" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "auth" ] && [ "\$2" = "status" ]; then
  exit 0
fi
if [ "\$1" = "repo" ] && [ "\$2" = "clone" ]; then
  mkdir -p "\$4"
  cp -R "$BATS_TEST_TMPDIR/fake-upstream/." "\$4/"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/gh"

  run env -u CLM_VAULT -u CLM_DOTFILES_DIR -u CLM_SETTINGS_DIR PATH="$FAKE_BIN:/usr/bin:/bin" CLM_MACHINE_NAME="test-machine" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/clm-install.sh" "someone/cl-settings"
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew bundle complete"* ]]
  [ -L "$CLM_TARGET/.zshrc" ]
}

@test "resumability: running clm-install.sh a second time stays successful and doesn't redo auth or clone" {
  write_fake_brew
  write_real_stow
  FAKE_UPSTREAM="$BATS_TEST_TMPDIR/fake-upstream/test-machine"
  mkdir -p "$FAKE_UPSTREAM/dotfiles/zsh" "$FAKE_UPSTREAM/vault/global/ssh/keys" "$FAKE_UPSTREAM/vault/bin" "$FAKE_UPSTREAM/pack"
  echo 'export FOO=1' > "$FAKE_UPSTREAM/dotfiles/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/../lib/clm/templates/fix-perms.sh" "$FAKE_UPSTREAM/vault/bin/fix-perms.sh"
  chmod +x "$FAKE_UPSTREAM/vault/bin/fix-perms.sh"

  cat > "$FAKE_BIN/gh" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "auth" ] && [ "\$2" = "status" ]; then
  exit 0
fi
if [ "\$1" = "auth" ] && [ "\$2" = "login" ]; then
  echo "login called" >> "$BREW_PREFIX/gh-login.log"
  exit 0
fi
if [ "\$1" = "repo" ] && [ "\$2" = "clone" ]; then
  echo "clone called" >> "$BREW_PREFIX/gh-clone.log"
  mkdir -p "\$4"
  cp -R "$BATS_TEST_TMPDIR/fake-upstream/." "\$4/"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/gh"

  env -u CLM_VAULT -u CLM_DOTFILES_DIR -u CLM_SETTINGS_DIR PATH="$FAKE_BIN:/usr/bin:/bin" CLM_MACHINE_NAME="test-machine" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/clm-install.sh" "someone/cl-settings"
  first_clone_calls="$(wc -l < "$BREW_PREFIX/gh-clone.log")"

  run env -u CLM_VAULT -u CLM_DOTFILES_DIR -u CLM_SETTINGS_DIR PATH="$FAKE_BIN:/usr/bin:/bin" CLM_MACHINE_NAME="test-machine" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/clm-install.sh" "someone/cl-settings"
  [ "$status" -eq 0 ]
  [ ! -e "$BREW_PREFIX/gh-login.log" ]
  second_clone_calls="$(wc -l < "$BREW_PREFIX/gh-clone.log")"
  [ "$first_clone_calls" -eq "$second_clone_calls" ]
}

@test "ensure_clm_on_path adds the PATH line to .zshenv when absent" {
  write_fake_brew
  write_fake_stow
  zshenv="$BATS_TEST_TMPDIR/zshenv"
  run env PATH="$FAKE_BIN:/usr/bin:/bin" CLM_ZSHENV="$zshenv" "$CLM_ROOT/clm-install.sh"
  grep -qF 'export PATH="$HOME/clm/bin:$PATH"' "$zshenv"
}

@test "ensure_clm_on_path is idempotent across two runs" {
  write_fake_brew
  write_fake_stow
  zshenv="$BATS_TEST_TMPDIR/zshenv"
  env PATH="$FAKE_BIN:/usr/bin:/bin" CLM_ZSHENV="$zshenv" "$CLM_ROOT/clm-install.sh" || true
  env PATH="$FAKE_BIN:/usr/bin:/bin" CLM_ZSHENV="$zshenv" "$CLM_ROOT/clm-install.sh" || true
  [ "$(grep -cF 'export PATH="$HOME/clm/bin:$PATH"' "$zshenv")" -eq 1 ]
}

@test "clm ends up on PATH via .zshenv even when cl-settings is never found" {
  write_fake_brew
  write_fake_stow
  zshenv="$BATS_TEST_TMPDIR/zshenv"
  run env PATH="$FAKE_BIN:/usr/bin:/bin" CLM_ZSHENV="$zshenv" CLM_MACHINE_NAME="brand-new-machine" "$CLM_ROOT/clm-install.sh"
  [ "$status" -ne 0 ]
  grep -qF 'export PATH="$HOME/clm/bin:$PATH"' "$zshenv"
}
