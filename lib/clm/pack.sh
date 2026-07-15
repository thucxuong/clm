#!/usr/bin/env bash

CLM_PACK_DIR="${CLM_PACK_DIR:-$CLM_ROOT/pack}"

clm::pack_checkers() {
  cat <<'EOF'
brew
mas
vscode
cursor
npm
pnpm
EOF
}

clm::pack_available() {
  case "$1" in
    brew) command -v brew >/dev/null 2>&1 ;;
    mas) command -v mas >/dev/null 2>&1 ;;
    vscode) command -v code >/dev/null 2>&1 ;;
    cursor) command -v cursor >/dev/null 2>&1 ;;
    npm) command -v npm >/dev/null 2>&1 ;;
    pnpm) command -v pnpm >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

clm::pack_valid_checker() {
  case "$1" in
    brew|mas|vscode|cursor|npm|pnpm) return 0 ;;
    *) return 1 ;;
  esac
}

clm::pack_run() {
  local checker="$1"
  mkdir -p "$CLM_PACK_DIR"
  case "$checker" in
    brew)
      brew bundle dump --force --file="$CLM_PACK_DIR/Brewfile" || clm::die "brew bundle dump failed"
      echo "packed: brew -> $CLM_PACK_DIR/Brewfile"
      ;;
    mas)
      mas list > "$CLM_PACK_DIR/mas.txt" || clm::die "mas list failed"
      echo "packed: mas -> $CLM_PACK_DIR/mas.txt"
      ;;
    vscode)
      code --list-extensions > "$CLM_PACK_DIR/vscode-extensions.txt" || clm::die "code --list-extensions failed"
      echo "packed: vscode -> $CLM_PACK_DIR/vscode-extensions.txt"
      ;;
    cursor)
      cursor --list-extensions > "$CLM_PACK_DIR/cursor-extensions.txt" || clm::die "cursor --list-extensions failed"
      echo "packed: cursor -> $CLM_PACK_DIR/cursor-extensions.txt"
      ;;
    npm)
      npm ls -g --depth=0 > "$CLM_PACK_DIR/npm-global.txt" || clm::die "npm ls -g failed"
      echo "packed: npm -> $CLM_PACK_DIR/npm-global.txt"
      ;;
    pnpm)
      pnpm list -g --depth=0 > "$CLM_PACK_DIR/pnpm-global.txt" || clm::die "pnpm list -g failed"
      echo "packed: pnpm -> $CLM_PACK_DIR/pnpm-global.txt"
      ;;
    *) clm::die "unknown pack checker: $checker" ;;
  esac
}

cmd_pack_list() {
  local c
  while IFS= read -r c; do
    if clm::pack_available "$c"; then
      echo "$c [available]"
    else
      echo "$c [not present]"
    fi
  done < <(clm::pack_checkers)
}

cmd_pack_one() {
  local checker="$1"
  clm::pack_valid_checker "$checker" || clm::die "unknown pack checker: $checker"
  if ! clm::pack_available "$checker"; then
    echo "skip (not present): $checker"
    return 0
  fi
  clm::pack_run "$checker"
}

cmd_pack_all() {
  local c
  while IFS= read -r c; do
    cmd_pack_one "$c"
  done < <(clm::pack_checkers)
}
