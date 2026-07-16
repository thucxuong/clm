# clm PATH via ~/.zshenv Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `clm` ends up on `PATH` (after a new shell) regardless of whether the rest of `clm-install.sh` succeeds, per the addendum in `docs/superpowers/specs/2026-07-15-clm-settings-consolidation-design.md`.

**Architecture:** New `ensure_clm_on_path()` in `clm-install.sh`, idempotently appending a `PATH` line to `~/.zshenv` (overridable via `CLM_ZSHENV`), called early in `main()` — before `ensure_gh_auth`/`ensure_cl_settings`/`clm unpack`, so it always runs even if those later steps fail.

**Tech Stack:** Bash (bash 3.2 compatible), bats-core.

## Global Constraints

- `ensure_clm_on_path` must never touch `~/.zshrc` (that stays exclusively Stow-managed, via `cl-settings`) — only `~/.zshenv`.
- Idempotent: running twice must not duplicate the line.
- Tests use `CLM_ZSHENV` pointing at a temp file, never the real `~/.zshenv`.

---

## Task 1: `ensure_clm_on_path`

**Files:**
- Modify: `clm-install.sh`
- Modify: `tests/clm_install_test.bats`

**Interfaces:**
- Produces: `ensure_clm_on_path()` — appends `export PATH="$HOME/clm/bin:$PATH"` to `${CLM_ZSHENV:-$HOME/.zshenv}` if not already present.

- [ ] **Step 1: Write the failing tests**

Append to `tests/clm_install_test.bats`:

```bash

@test "ensure_clm_on_path adds the PATH line to .zshenv when absent" {
  write_fake_brew
  write_fake_stow
  zshenv="$BATS_TEST_TMPDIR/zshenv"
  run env PATH="$FAKE_BIN:/usr/bin:/bin" CLM_ZSHENV="$zshenv" "$CLM_ROOT/clm-install.sh"
  grep -qF 'export PATH="$HOME/clm/bin:$PATH"' "$zshenv"
}

@test "ensure_clm_on_path is idempotent across two runs" {
  write_fake_brew
  write_fake_stow
  zshenv="$BATS_TEST_TMPDIR/zshenv"
  env PATH="$FAKE_BIN:/usr/bin:/bin" CLM_ZSHENV="$zshenv" "$CLM_ROOT/clm-install.sh" || true
  env PATH="$FAKE_BIN:/usr/bin:/bin" CLM_ZSHENV="$zshenv" "$CLM_ROOT/clm-install.sh" || true
  [ "$(grep -cF 'export PATH="$HOME/clm/bin:$PATH"' "$zshenv")" -eq 1 ]
}

@test "clm ends up on PATH via .zshenv even when cl-settings is never found" {
  write_fake_brew
  write_fake_stow
  zshenv="$BATS_TEST_TMPDIR/zshenv"
  run env PATH="$FAKE_BIN:/usr/bin:/bin" CLM_ZSHENV="$zshenv" CLM_MACHINE_NAME="brand-new-machine" "$CLM_ROOT/clm-install.sh"
  [ "$status" -ne 0 ]
  grep -qF 'export PATH="$HOME/clm/bin:$PATH"' "$zshenv"
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/clm_install_test.bats`
Expected: FAIL — `ensure_clm_on_path` doesn't exist yet; `CLM_ZSHENV` is never read.

- [ ] **Step 3: Implement `ensure_clm_on_path` in `clm-install.sh`**

Add after `ensure_gh`:

```bash
ensure_clm_on_path() {
  local zshenv="${CLM_ZSHENV:-$HOME/.zshenv}"
  local path_line='export PATH="$HOME/clm/bin:$PATH"'
  if [ -f "$zshenv" ] && grep -qF "$path_line" "$zshenv"; then
    echo "clm PATH: already in $zshenv"
    return
  fi
  echo "$path_line" >> "$zshenv"
  echo "clm PATH: added to $zshenv"
}
```

Update `main()` — call it right after `chmod +x`, before `ensure_gh_auth`, and simplify the final message (it no longer needs to explain `.zshrc`):

```bash
main() {
  local settings_repo="${1:-}"
  ensure_homebrew
  ensure_stow
  ensure_gh
  chmod +x "$CLM_ROOT/bin/clm"
  ensure_clm_on_path
  ensure_gh_auth
  ensure_cl_settings "$settings_repo"
  "$CLM_ROOT/bin/clm" unpack
  cat <<EOF

Done. Open a new terminal (or run: exec \$SHELL) so 'clm' is on your PATH.
EOF
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/clm_install_test.bats`
Expected: `15 tests, 0 failures`

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `bats tests/`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add clm-install.sh tests/clm_install_test.bats
git commit -m "clm PATH now comes from ~/.zshenv, set unconditionally before cl-settings/unpack can fail"
```

---

## Task 2: README update

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the PATH explanation**

Replace:

```markdown
`clm` itself goes on `PATH` via a line in your own `zsh/.zshrc` (part of
`cl-settings`, stowed during `clm unpack`) — not via Homebrew, so it isn't
tied to wherever Homebrew happens to live. Open a new terminal after the
first run for that to take effect.
```

with:

```markdown
`clm` itself goes on `PATH` via a line `clm-install.sh` adds to
`~/.zshenv` (not via Homebrew, and not via `cl-settings`/Stow either) —
zsh reads `.zshenv` on every invocation, so this is set up before
anything that could fail (like `cl-settings` not yet having a folder for
a brand-new machine) has a chance to block it. Open a new terminal after
the first run for that to take effect.
```

Update the "Setting up an additional (not-yet-seen) machine" section to drop the full-path caveat since it's no longer needed after this fix — but note it's still needed on the *very first* run before `.zshenv` has been picked up by a new shell:

```markdown
### Setting up an additional (not-yet-seen) machine

`cl-settings` is namespaced per machine (`cl-settings/<machine-name>/`).
If this is a genuinely new machine — not a reinstall of one already in
`cl-settings` — `clm unpack` will correctly say `cl-settings not found`
for *this* machine's subfolder, even though `cl-settings` itself cloned
fine, `clm-install.sh` will already have added `clm` to `~/.zshenv` before
that failure though, so **open a new terminal first**, then:

    clm settings new --from <existing-machine-name>
    clm-install.sh thucxuong/cl-settings

(Re-running `clm-install.sh` is resumable — it skips everything already
done and picks up at `clm unpack`, which now succeeds.) `--from` copies
that machine's dotfiles as an editable starting point. `vault/` always
starts empty — add real SSH keys yourself under
`cl-settings/<this-machine>/vault/`, then run `clm vault fix-perms`.
```

- [ ] **Step 2: Run the full test suite one more time**

Run: `bats tests/`
Expected: all tests pass, `0 failures`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Update README for the .zshenv-based PATH fix"
```
