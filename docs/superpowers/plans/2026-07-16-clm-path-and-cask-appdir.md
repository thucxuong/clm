# Decouple clm PATH from Homebrew; ~/Applications for Casks

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two independent fixes agreed with the user: (1) stop symlinking `clm` into Homebrew's bin dir — put it on `PATH` via the user's own `.zshrc` instead, decoupling `clm`'s availability from Homebrew's location entirely; (2) install Homebrew casks into `~/Applications` instead of `/Applications`, avoiding the admin-group write requirement for app installs.

**Architecture:** Remove `link_clm_cli` from `clm-install.sh`. Set `HOMEBREW_CASK_OPTS` before `brew bundle` in `cmd_unpack`. Add the `PATH` export and `HOMEBREW_CASK_OPTS` export to the real `zsh/.zshrc` in `cl-settings` (a separate repo, its own commit) so both apply to every future interactive shell too, not just the bootstrap run.

**Tech Stack:** Bash (bash 3.2 compatible), bats-core.

## Global Constraints

- Same bash 3.2 constraints as prior plans.
- `cl-settings` changes are real personal dotfile content, committed separately from the `clm` engine changes.

---

## Task 1: Remove Homebrew-based `clm` linking

**Files:**
- Modify: `clm-install.sh`
- Modify: `tests/clm_install_test.bats`
- Modify: `README.md`

- [ ] **Step 1: Update the test**

Replace:

```bash
@test "install links clm into the brew prefix when brew and stow are present" {
  write_fake_brew
  write_fake_stow
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  [ -L "$BREW_PREFIX/bin/clm" ]
}
```

with:

```bash
@test "install makes bin/clm executable without touching the brew prefix" {
  write_fake_brew
  write_fake_stow
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  [ -x "$CLM_ROOT/bin/clm" ]
  [ ! -e "$BREW_PREFIX/bin/clm" ]
}
```

- [ ] **Step 2: Run the tests to verify this one fails**

Run: `bats tests/clm_install_test.bats`
Expected: FAIL on the updated test (current code still symlinks into the brew prefix); all others still pass.

- [ ] **Step 3: Remove `link_clm_cli` and its call in `clm-install.sh`**

Delete the function:

```bash
link_clm_cli() {
  chmod +x "$CLM_ROOT/bin/clm"
  local prefix
  prefix="$(brew --prefix)"
  mkdir -p "$prefix/bin"
  ln -sf "$CLM_ROOT/bin/clm" "$prefix/bin/clm"
  echo "linked: $prefix/bin/clm -> $CLM_ROOT/bin/clm"
}
```

Update `main()`:

```bash
main() {
  local settings_repo="${1:-}"
  ensure_homebrew
  ensure_stow
  ensure_gh
  chmod +x "$CLM_ROOT/bin/clm"
  ensure_gh_auth
  ensure_cl_settings "$settings_repo"
  "$CLM_ROOT/bin/clm" unpack
  cat <<EOF

Done. Open a new terminal (or run: exec \$SHELL) so 'clm' is on your PATH.
It's added via ~/.zshrc, picked up by new shells — not this one.
EOF
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/clm_install_test.bats`
Expected: `12 tests, 0 failures`

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `bats tests/`
Expected: 0 failures.

- [ ] **Step 6: Update `README.md`**

Change the note after the one-liner code block:

```markdown
That's it — one command. It clones `~/clm`, then hands off to
`clm-install.sh`: Homebrew, Stow, and `gh` get installed if missing,
`gh auth login` runs if you're not already authenticated (browser-based —
no SSH key needed), `cl-settings` gets cloned if it isn't already present,
and `clm unpack` runs at the end (stow onboard + vault fix-perms + brew
bundle + npm/pnpm globals + VS Code/Cursor extensions). Every step checks
its own precondition first, so if this gets interrupted partway (network
blip, closed terminal mid-`gh auth login`), just run the same command
again — nothing gets redone unnecessarily, and it picks up wherever it
left off.

`clm` itself goes on `PATH` via a line in your own `zsh/.zshrc` (part of
`cl-settings`, stowed during `clm unpack`) — not via Homebrew, so it isn't
tied to wherever Homebrew happens to live. Open a new terminal after the
first run for that to take effect.
```

- [ ] **Step 7: Commit**

```bash
git add clm-install.sh tests/clm_install_test.bats README.md
git commit -m "Stop linking clm into Homebrew's bin dir; PATH comes from .zshrc instead"
```

---

## Task 2: `~/Applications` for Homebrew casks

**Files:**
- Modify: `lib/clm/unpack.sh`
- Modify: `tests/unpack_test.bats`
- Modify: `README.md`

**Interfaces:**
- `cmd_unpack`'s `brew bundle` invocation now runs with `HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"` set.

- [ ] **Step 1: Write the failing test**

Add to `tests/unpack_test.bats`, right after `"clm unpack runs brew bundle when a Brewfile is present"`:

```bash

@test "clm unpack installs casks into ~/Applications, not /Applications" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh" "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"
  echo '# empty brewfile' > "$settings_dir/pack/Brewfile"
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  ln -s "$(command -v stow)" "$FAKE_BIN/stow"
  cat > "$FAKE_BIN/brew" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "bundle" ]; then
  echo "HOMEBREW_CASK_OPTS=\$HOMEBREW_CASK_OPTS" >> "$BATS_TEST_TMPDIR/brew-bundle-env.log"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/brew"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  grep -q -- "--appdir=$HOME/Applications" "$BATS_TEST_TMPDIR/brew-bundle-env.log"
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/unpack_test.bats`
Expected: FAIL — `HOMEBREW_CASK_OPTS` isn't set yet.

- [ ] **Step 3: Update `cmd_unpack` in `lib/clm/unpack.sh`**

Change:

```bash
  if [ -f "$CLM_SETTINGS_DIR/pack/Brewfile" ]; then
    brew bundle --file="$CLM_SETTINGS_DIR/pack/Brewfile" || clm::die "brew bundle failed"
    echo "brew bundle complete"
  else
```

to:

```bash
  if [ -f "$CLM_SETTINGS_DIR/pack/Brewfile" ]; then
    HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications" brew bundle --file="$CLM_SETTINGS_DIR/pack/Brewfile" || clm::die "brew bundle failed"
    echo "brew bundle complete"
  else
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/unpack_test.bats`
Expected: `11 tests, 0 failures`

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `bats tests/`
Expected: 0 failures.

- [ ] **Step 6: Update `README.md`**'s Safety section

Add a bullet:

```markdown
- `clm unpack`'s `brew bundle` step installs casks (GUI apps) into
  `~/Applications` rather than the shared `/Applications`, so it never
  needs admin-group write access.
```

- [ ] **Step 7: Commit**

```bash
git add lib/clm/unpack.sh tests/unpack_test.bats README.md
git commit -m "clm unpack: install casks into ~/Applications, avoiding admin-group requirement"
```

---

## Task 3: Update the real `cl-settings` dotfiles (separate repo, separate commit)

**Files (in `cl-settings`, not the `clm` engine):**
- Modify: `cl-settings/<machine>/dotfiles/zsh/.zshrc`

This is real personal content, not covered by the engine's test suite.

- [ ] **Step 1: Add two lines to the real `zsh/.zshrc`**

```sh
export PATH="$HOME/clm/bin:$PATH"
export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
```

Append them near the top of the file (before anything that might depend on `clm` or brew-installed tools being on `PATH`), or wherever fits the file's existing structure best — read the file first to place them sensibly rather than blindly appending at the very end.

- [ ] **Step 2: Verify the file is valid shell**

Run: `zsh -n "cl-settings/<machine>/dotfiles/zsh/.zshrc"` (syntax check only, does not execute)
Expected: no output, exit 0.

- [ ] **Step 3: Commit in the `cl-settings` repo**

```bash
cd cl-settings
git add <machine>/dotfiles/zsh/.zshrc
git commit -m "Add clm PATH and HOMEBREW_CASK_OPTS to zsh config"
git push
```
