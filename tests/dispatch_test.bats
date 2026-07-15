#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
  mkdir -p "$CLM_DOTFILES_DIR/zsh"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
}

@test "clm with no args prints usage and exits 1" {
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" "$CLM_ROOT/bin/clm"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: clm"* ]]
}

@test "clm with an unknown noun prints usage and exits 1" {
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" "$CLM_ROOT/bin/clm" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: clm"* ]]
}

@test "clm stow with an unknown verb prints usage and exits 1" {
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" "$CLM_ROOT/bin/clm" stow bogus
  [ "$status" -eq 1 ]
}

@test "clm stow add works end to end through the dispatcher" {
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" "$CLM_ROOT/bin/clm" stow add zsh
  [ "$status" -eq 0 ]
  [ -L "$CLM_TARGET/.zshrc" ]
}

@test "--yes is parsed and not treated as a package name" {
  env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" "$CLM_ROOT/bin/clm" stow add zsh
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" "$CLM_ROOT/bin/clm" stow remove zsh --yes
  [ "$status" -eq 0 ]
  [ ! -e "$CLM_TARGET/.zshrc" ]
}

@test "clm resolves its root correctly even when invoked through a symlink" {
  ln -s "$CLM_ROOT/bin/clm" "$BATS_TEST_TMPDIR/clm-link"
  run env CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" "$BATS_TEST_TMPDIR/clm-link" stow add zsh
  [ "$status" -eq 0 ]
  [ -L "$CLM_TARGET/.zshrc" ]
}
