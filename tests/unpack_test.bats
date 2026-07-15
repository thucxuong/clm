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
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
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
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
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

@test "clm unpack restores npm globals, correctly stripping scoped and unscoped versions" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh" "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"
  cat > "$settings_dir/pack/npm-global.txt" <<'EOF'
/Users/x/.nvm/versions/node/v22.14.0/lib
├── @google/gemini-cli@
├── clerk@1.5.0
└── vercel@54.14.2
EOF
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  ln -s "$(command -v stow)" "$FAKE_BIN/stow"
  cat > "$FAKE_BIN/npm" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "install" ] && [ "\$2" = "-g" ]; then
  echo "npm install -g \$3" >> "$BATS_TEST_TMPDIR/npm-calls.log"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/npm"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  grep -q "npm install -g @google/gemini-cli$" "$BATS_TEST_TMPDIR/npm-calls.log"
  grep -q "npm install -g clerk$" "$BATS_TEST_TMPDIR/npm-calls.log"
  grep -q "npm install -g vercel$" "$BATS_TEST_TMPDIR/npm-calls.log"
}

@test "clm unpack skips npm restore gracefully when npm-global.txt is absent" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh" "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  [[ "$output" == *"no npm-global.txt found"* ]]
}

@test "clm unpack skips npm restore gracefully when npm is not installed" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh" "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"
  echo "clerk@1.5.0" > "$settings_dir/pack/npm-global.txt"
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  ln -s "$(command -v stow)" "$FAKE_BIN/stow"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  [[ "$output" == *"npm not installed"* ]]
}

@test "clm unpack restores pnpm globals from the dependencies section only" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh" "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"
  cat > "$settings_dir/pack/pnpm-global.txt" <<'EOF'
Legend: production dependency, optional only, dev only

/Users/x/Library/pnpm/global/5

dependencies:
@google/gemini-cli 0.20.2
aws-cdk 2.1027.0
EOF
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  ln -s "$(command -v stow)" "$FAKE_BIN/stow"
  cat > "$FAKE_BIN/pnpm" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "add" ] && [ "\$2" = "-g" ]; then
  echo "pnpm add -g \$3" >> "$BATS_TEST_TMPDIR/pnpm-calls.log"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/pnpm"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  grep -q "pnpm add -g @google/gemini-cli$" "$BATS_TEST_TMPDIR/pnpm-calls.log"
  grep -q "pnpm add -g aws-cdk$" "$BATS_TEST_TMPDIR/pnpm-calls.log"
  ! grep -q "Legend" "$BATS_TEST_TMPDIR/pnpm-calls.log"
}

@test "clm unpack restores vscode extensions one per line" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh" "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"
  printf 'alefragnani.bookmarks\nangular.ng-template\n' > "$settings_dir/pack/vscode-extensions.txt"
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  ln -s "$(command -v stow)" "$FAKE_BIN/stow"
  cat > "$FAKE_BIN/code" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "--install-extension" ]; then
  echo "code --install-extension \$2" >> "$BATS_TEST_TMPDIR/code-calls.log"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/code"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  grep -q "code --install-extension alefragnani.bookmarks" "$BATS_TEST_TMPDIR/code-calls.log"
  grep -q "code --install-extension angular.ng-template" "$BATS_TEST_TMPDIR/code-calls.log"
}

@test "clm unpack skips vscode restore gracefully when code is not installed" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh" "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"
  echo "alefragnani.bookmarks" > "$settings_dir/pack/vscode-extensions.txt"
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  ln -s "$(command -v stow)" "$FAKE_BIN/stow"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  [[ "$output" == *"code not installed"* ]]
}

@test "clm unpack restores cursor extensions one per line" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh" "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"
  printf 'alefragnani.bookmarks\n' > "$settings_dir/pack/cursor-extensions.txt"
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  ln -s "$(command -v stow)" "$FAKE_BIN/stow"
  cat > "$FAKE_BIN/cursor" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "--install-extension" ]; then
  echo "cursor --install-extension \$2" >> "$BATS_TEST_TMPDIR/cursor-calls.log"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/cursor"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  grep -q "cursor --install-extension alefragnani.bookmarks" "$BATS_TEST_TMPDIR/cursor-calls.log"
}
