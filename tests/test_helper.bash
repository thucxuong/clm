setup_clm_env() {
  CLM_ROOT="$BATS_TEST_TMPDIR/clm-root"
  CLM_TARGET="$BATS_TEST_TMPDIR/home"
  CLM_DOTFILES_DIR="$CLM_ROOT/dotfiles"
  CLM_VAULT="$CLM_ROOT/vault"
  export CLM_ROOT CLM_TARGET CLM_DOTFILES_DIR CLM_VAULT
  mkdir -p "$CLM_ROOT/bin" "$CLM_ROOT/lib/clm" "$CLM_TARGET" "$CLM_DOTFILES_DIR"
  cp "$BATS_TEST_DIRNAME/../bin/clm" "$CLM_ROOT/bin/clm" 2>/dev/null || true
  cp "$BATS_TEST_DIRNAME"/../lib/clm/*.sh "$CLM_ROOT/lib/clm/" 2>/dev/null || true
  chmod +x "$CLM_ROOT/bin/clm" 2>/dev/null || true
}
