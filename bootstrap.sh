#!/usr/bin/env sh
set -e

REPO_SLUG="${1:-}"
CLM_DIR="${CLM_BOOTSTRAP_DIR:-$HOME/clm}"

if [ -d "$CLM_DIR" ]; then
  echo "clm: found at $CLM_DIR"
else
  git clone https://github.com/thucxuong/clm.git "$CLM_DIR"
fi

exec "$CLM_DIR/clm-install.sh" "$REPO_SLUG"
