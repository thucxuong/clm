#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
}

@test "clm settings new refuses when cl-settings root doesn't exist" {
  run env CLM_ROOT="$CLM_ROOT" CLM_MACHINE_NAME="new-machine" "$CLM_ROOT/bin/clm" settings new
  [ "$status" -ne 0 ]
  [[ "$output" == *"cl-settings not found"* ]]
}

@test "clm settings new refuses when the target machine folder already exists" {
  mkdir -p "$CLM_ROOT/cl-settings/new-machine"
  run env CLM_ROOT="$CLM_ROOT" CLM_MACHINE_NAME="new-machine" "$CLM_ROOT/bin/clm" settings new
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "clm settings new scaffolds an empty skeleton for the current machine with no --from" {
  mkdir -p "$CLM_ROOT/cl-settings"
  run env CLM_ROOT="$CLM_ROOT" CLM_MACHINE_NAME="new-machine" "$CLM_ROOT/bin/clm" settings new
  [ "$status" -eq 0 ]
  [ -d "$CLM_ROOT/cl-settings/new-machine/dotfiles" ]
  [ -x "$CLM_ROOT/cl-settings/new-machine/vault/bin/fix-perms.sh" ]
  [ -d "$CLM_ROOT/cl-settings/new-machine/vault/global/ssh/keys" ]
  [ -d "$CLM_ROOT/cl-settings/new-machine/pack" ]
  [ -z "$(ls -A "$CLM_ROOT/cl-settings/new-machine/dotfiles")" ]
}

@test "clm settings new copies dotfiles from --from and fixes up the ssh config's machine path" {
  mkdir -p "$CLM_ROOT/cl-settings/old-machine/dotfiles/zsh" "$CLM_ROOT/cl-settings/old-machine/dotfiles/ssh/.ssh"
  echo 'export FOO=1' > "$CLM_ROOT/cl-settings/old-machine/dotfiles/zsh/.zshrc"
  cat > "$CLM_ROOT/cl-settings/old-machine/dotfiles/ssh/.ssh/config" <<'EOF'
Include ~/clm/cl-settings/old-machine/vault/global/ssh/config
Include ~/clm/cl-settings/old-machine/vault/projects/*/ssh/config

Host *
    IdentitiesOnly yes
EOF

  run env CLM_ROOT="$CLM_ROOT" CLM_MACHINE_NAME="new-machine" "$CLM_ROOT/bin/clm" settings new new-machine --from old-machine
  [ "$status" -eq 0 ]
  [ -f "$CLM_ROOT/cl-settings/new-machine/dotfiles/zsh/.zshrc" ]
  grep -q "cl-settings/new-machine/vault/global/ssh/config" "$CLM_ROOT/cl-settings/new-machine/dotfiles/ssh/.ssh/config"
  grep -q "cl-settings/new-machine/vault/projects" "$CLM_ROOT/cl-settings/new-machine/dotfiles/ssh/.ssh/config"
  ! grep -q "old-machine" "$CLM_ROOT/cl-settings/new-machine/dotfiles/ssh/.ssh/config"
  [ ! -e "$CLM_ROOT/cl-settings/new-machine/vault/global/ssh/keys/id_rsa" ]
}

@test "clm settings new refuses when --from source machine doesn't exist" {
  mkdir -p "$CLM_ROOT/cl-settings"
  run env CLM_ROOT="$CLM_ROOT" CLM_MACHINE_NAME="new-machine" "$CLM_ROOT/bin/clm" settings new new-machine --from nonexistent-machine
  [ "$status" -ne 0 ]
  [[ "$output" == *"nonexistent-machine"* ]]
}
