#!/usr/bin/env bash

clm::stow_packages() {
  local entry
  for entry in "$CLM_DOTFILES_DIR"/*/; do
    [ -d "$entry" ] || continue
    basename "$entry"
  done
}

clm::is_stowed() {
  local pkg="$1"
  local pkg_dir
  pkg_dir="$(cd -P "$CLM_DOTFILES_DIR/$pkg" 2>/dev/null && pwd)" || return 1
  local file rel target_file link_target resolved
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    rel="${file#"$pkg_dir"/}"
    target_file="$CLM_TARGET/$rel"
    [ -L "$target_file" ] || return 1
    link_target="$(readlink "$target_file")"
    case "$link_target" in
      /*) : ;;
      *) link_target="$(dirname "$target_file")/$link_target" ;;
    esac
    resolved="$(cd -P "$(dirname "$link_target")" 2>/dev/null && pwd)/$(basename "$link_target")" || return 1
    [ "$resolved" = "$file" ] || return 1
  done < <(find "$pkg_dir" -type f)
  return 0
}

clm::validate_package() {
  local pkg="$1"
  [ -d "$CLM_DOTFILES_DIR/$pkg" ] || clm::die "no such package: $pkg"
}

cmd_stow_add() {
  local pkg="$1"
  clm::validate_package "$pkg"
  stow --no-folding -d "$CLM_DOTFILES_DIR" -t "$CLM_TARGET" "$pkg" || clm::die "stow failed for '$pkg' (see conflicts above)"
  echo "stowed: $pkg"
}

cmd_stow_remove() {
  local pkg="$1"
  clm::validate_package "$pkg"
  clm::confirm "Unstow '$pkg' (remove its symlinks from $CLM_TARGET)?" || clm::die "aborted"
  stow --no-folding -D -d "$CLM_DOTFILES_DIR" -t "$CLM_TARGET" "$pkg" || clm::die "unstow failed for '$pkg'"
  echo "unstowed: $pkg"
}

cmd_stow_onboard() {
  local pkg
  for pkg in zsh bash git ssh; do
    if [ ! -d "$CLM_DOTFILES_DIR/$pkg" ]; then
      echo "skip (not present): $pkg"
      continue
    fi
    stow --no-folding -d "$CLM_DOTFILES_DIR" -t "$CLM_TARGET" "$pkg" || clm::die "stow failed for '$pkg' (see conflicts above)"
    echo "stowed: $pkg"
  done
}

cmd_stow_list() {
  local pkg
  while IFS= read -r pkg; do
    if clm::is_stowed "$pkg"; then
      echo "$pkg [stowed]"
    else
      echo "$pkg [not stowed]"
    fi
  done < <(clm::stow_packages)
}
