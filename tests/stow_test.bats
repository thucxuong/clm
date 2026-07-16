#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
  mkdir -p "$CLM_DOTFILES_DIR/zsh"
  echo 'export FOO=1' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
}

@test "stow_packages lists zsh" {
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET' CLM_DOTFILES_DIR='$CLM_DOTFILES_DIR'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    clm::stow_packages
  "
  [[ "$output" == *"zsh"* ]]
}

@test "is_stowed is false before stowing and true after" {
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET' CLM_DOTFILES_DIR='$CLM_DOTFILES_DIR'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    clm::is_stowed zsh
  "
  [ "$status" -eq 1 ]

  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET' CLM_DOTFILES_DIR='$CLM_DOTFILES_DIR'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_add zsh >/dev/null
    clm::is_stowed zsh
  "
  [ "$status" -eq 0 ]
}

@test "cmd_stow_add links the package into target" {
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET' CLM_DOTFILES_DIR='$CLM_DOTFILES_DIR'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_add zsh
  "
  [ "$status" -eq 0 ]
  [ -L "$CLM_TARGET/.zshrc" ]
}

@test "cmd_stow_add refuses an unknown package" {
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET' CLM_DOTFILES_DIR='$CLM_DOTFILES_DIR'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_add nonexistent
  "
  [ "$status" -ne 0 ]
}

@test "cmd_stow_add backs up a conflicting non-symlink file and succeeds" {
  mkdir -p "$CLM_TARGET"
  echo 'not managed by stow' > "$CLM_TARGET/.zshrc"
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET' CLM_DOTFILES_DIR='$CLM_DOTFILES_DIR'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_add zsh
  "
  [ "$status" -eq 0 ]
  [ -L "$CLM_TARGET/.zshrc" ]
  [ -f "$CLM_TARGET/.zshrc.clm-backup" ]
  [ "$(cat "$CLM_TARGET/.zshrc.clm-backup")" = "not managed by stow" ]
}

@test "cmd_stow_add does not clobber an existing .clm-backup, uses a numbered suffix instead" {
  mkdir -p "$CLM_TARGET"
  echo 'first conflict' > "$CLM_TARGET/.zshrc"
  echo 'earlier backup, keep me' > "$CLM_TARGET/.zshrc.clm-backup"
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET' CLM_DOTFILES_DIR='$CLM_DOTFILES_DIR'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_add zsh
  "
  [ "$status" -eq 0 ]
  [ -L "$CLM_TARGET/.zshrc" ]
  [ "$(cat "$CLM_TARGET/.zshrc.clm-backup")" = "earlier backup, keep me" ]
  [ -f "$CLM_TARGET/.zshrc.clm-backup.1" ]
  [ "$(cat "$CLM_TARGET/.zshrc.clm-backup.1")" = "first conflict" ]
}

@test "cmd_stow_remove asks for confirmation and removes the symlink when confirmed" {
  bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET' CLM_DOTFILES_DIR='$CLM_DOTFILES_DIR'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_add zsh
  "
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET' CLM_DOTFILES_DIR='$CLM_DOTFILES_DIR'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    echo y | cmd_stow_remove zsh
  "
  [ "$status" -eq 0 ]
  [ ! -e "$CLM_TARGET/.zshrc" ]
}

@test "cmd_stow_remove aborts when not confirmed" {
  bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET' CLM_DOTFILES_DIR='$CLM_DOTFILES_DIR'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_add zsh
  "
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET' CLM_DOTFILES_DIR='$CLM_DOTFILES_DIR'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    echo n | cmd_stow_remove zsh
  "
  [ "$status" -ne 0 ]
  [ -L "$CLM_TARGET/.zshrc" ]
}

@test "cmd_stow_onboard stows what's present and skips what isn't" {
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET' CLM_DOTFILES_DIR='$CLM_DOTFILES_DIR'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_onboard
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"stowed: zsh"* ]]
  [[ "$output" == *"skip (not present): bash"* ]]
}

@test "cmd_stow_list reports stowed state per package" {
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET' CLM_DOTFILES_DIR='$CLM_DOTFILES_DIR'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_add zsh >/dev/null
    cmd_stow_list
  "
  [[ "$output" == *"zsh [stowed]"* ]]
}
