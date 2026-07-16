#!/usr/bin/env bash

CLM_TEMPLATES_DIR="${CLM_TEMPLATES_DIR:-$CLM_ROOT/lib/clm/templates}"

cmd_settings_new() {
  local machine_name="${1:-$CLM_MACHINE_NAME}"
  local from_machine="$2"
  local cl_settings_root="$CLM_ROOT/cl-settings"
  local target="$cl_settings_root/$machine_name"

  [ -d "$cl_settings_root" ] || clm::die "cl-settings not found at $cl_settings_root (clone it first)"
  [ ! -d "$target" ] || clm::die "cl-settings/$machine_name already exists"

  local source=""
  if [ -n "$from_machine" ]; then
    source="$cl_settings_root/$from_machine"
    [ -d "$source/dotfiles" ] || clm::die "cl-settings/$from_machine not found"
  fi

  mkdir -p "$target/dotfiles" "$target/vault/global/ssh/keys" "$target/vault/projects" "$target/vault/bin" "$target/pack"

  if [ -n "$from_machine" ]; then
    local entry
    for entry in "$source/dotfiles"/*; do
      [ -e "$entry" ] || continue
      cp -R "$entry" "$target/dotfiles/"
    done
    if [ -f "$target/dotfiles/ssh/.ssh/config" ]; then
      sed -i '' "s#cl-settings/$from_machine/#cl-settings/$machine_name/#g" "$target/dotfiles/ssh/.ssh/config"
    fi
    echo "settings: copied dotfiles from $from_machine"

    if [ -d "$source/pack" ]; then
      for entry in "$source/pack"/*; do
        [ -e "$entry" ] || continue
        cp -R "$entry" "$target/pack/"
      done
      echo "settings: copied pack from $from_machine"
    fi
  fi

  cp "$CLM_TEMPLATES_DIR/fix-perms.sh" "$target/vault/bin/fix-perms.sh"
  chmod +x "$target/vault/bin/fix-perms.sh"
  cat > "$target/vault/global/ssh/config" <<'EOF'
# Host blocks for keys that should always be available, regardless of project.
# Example:
#
# Host github.com-personal
#     HostName github.com
#     User git
#     IdentityFile ~/clm/cl-settings/<machine>/vault/global/ssh/keys/id_ed25519_personal
EOF
  touch "$target/vault/global/ssh/keys/.gitkeep" "$target/vault/projects/.gitkeep"
  cat > "$target/vault/README.md" <<EOF
# vault ($machine_name)

Private secrets for this machine. Add real SSH keys under
global/ssh/keys/ or projects/<name>/ssh/keys/, then run:
clm vault fix-perms
EOF

  echo "settings: created cl-settings/$machine_name"
  cat <<EOF

Next steps:
  # add real SSH keys under cl-settings/$machine_name/vault/global/ssh/keys/
  clm vault fix-perms
  clm stow onboard
EOF
}
