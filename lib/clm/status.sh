#!/usr/bin/env bash

cmd_status() {
  echo "CLM root: $CLM_ROOT"
  echo
  echo "Stow packages:"
  local pkg
  while IFS= read -r pkg; do
    if clm::is_stowed "$pkg"; then
      echo "  $pkg [stowed]"
    else
      echo "  $pkg [not stowed]"
    fi
  done < <(clm::stow_packages)
  echo
  if [ -d "$CLM_VAULT" ]; then
    echo "Vault: found at $CLM_VAULT"
    if [ -d "$CLM_VAULT/global/ssh/keys" ]; then
      local perm
      perm="$(stat -f '%Lp' "$CLM_VAULT/global/ssh/keys")"
      if [ "$perm" = "700" ]; then
        echo "  global/ssh/keys perms: ok (700)"
      else
        echo "  global/ssh/keys perms: WARNING got $perm, expected 700 (run: clm vault fix-perms)"
      fi
    fi
  else
    echo "Vault: not found (clone it to $CLM_VAULT)"
  fi
}
