#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
}

@test "clm unpack refuses when cl-settings is not present" {
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$CLM_ROOT/does-not-exist" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -ne 0 ]
  [[ "$output" == *"cl-settings not found"* ]]
}

@test "clm unpack stows dotfiles, fixes vault perms, and reports no Brewfile when absent" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  mkdir -p "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  cp "$BATS_TEST_DIRNAME/../vault/bin/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  [ -L "$CLM_TARGET/.zshrc" ]
  [[ "$output" == *"skipping CLI tools/apps install"* ]]
}

@test "clm unpack runs brew bundle when a Brewfile is present" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  mkdir -p "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  cp "$BATS_TEST_DIRNAME/../vault/bin/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"
  echo '# empty brewfile' > "$settings_dir/pack/Brewfile"
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  cat > "$FAKE_BIN/brew" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "bundle" ]; then
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/brew"
  ln -s "$(command -v stow)" "$FAKE_BIN/stow"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew bundle complete"* ]]
}
