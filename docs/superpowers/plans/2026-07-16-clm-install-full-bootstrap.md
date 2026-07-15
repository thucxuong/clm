# Full Automated Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `clm-install.sh` a one-command, resumable, end-to-end bootstrap: install deps, authenticate `gh`, clone `cl-settings`, run `clm unpack` — per the addendum in `docs/superpowers/specs/2026-07-15-clm-settings-consolidation-design.md`.

**Architecture:** Two new idempotent functions in `clm-install.sh` (`ensure_gh_auth`, `ensure_cl_settings`), plus a final `"$CLM_ROOT/bin/clm" unpack` call in `main()`, which now accepts the `cl-settings` repo slug as `$1`.

**Tech Stack:** Bash (bash 3.2 compatible), `gh`, bats-core.

## Global Constraints

- Same bash 3.2 constraints as prior plans.
- Every new step must be idempotent (safe to re-run) — this is the entire resumability strategy, no state file.
- `ensure_cl_settings` clones into `$CLM_ROOT/cl-settings` (the repo root — it holds every machine's folder together), never `$CLM_SETTINGS_DIR` (this machine's subfolder within it).
- Tests use fake `gh`/`brew`/`stow` stubs; never invoke the real `gh auth login` (interactive/browser-based) or clone a real repo.
- Once `main()` calls through to `"$CLM_ROOT/bin/clm" unpack` at the end, tests that only care about an *earlier* step (e.g. "was `brew install stow` called") should assert on that step's own side effect, not on the overall script exit status — the script legitimately exits nonzero later if `cl-settings` isn't fully set up, which is correct behavior, not a test failure.

---

## Task 1: `ensure_gh_auth`, `ensure_cl_settings`, and the final `clm unpack` call

**Files:**
- Modify: `clm-install.sh`
- Modify: `tests/clm_install_test.bats`

**Interfaces:**
- Produces: `ensure_gh_auth()` — skips if `gh auth status` succeeds, else runs `gh auth login`. `ensure_cl_settings(repo_slug)` — skips if `$CLM_ROOT/cl-settings` already exists; if absent and `repo_slug` is non-empty, runs `gh repo clone "$repo_slug" "$CLM_ROOT/cl-settings"`; if absent and `repo_slug` is empty, prints a message and returns 0 without erroring.
- `main()` now takes the repo slug as `$1` and finishes with `"$CLM_ROOT/bin/clm" unpack`.

- [ ] **Step 1: Adjust the three existing tests whose assertions checked overall exit status, which is no longer meaningful once `main()` chains through to `clm unpack`**

In `tests/clm_install_test.bats`, first extend `write_fake_brew` to also handle `bundle` (needed by later end-to-end tests in this task; harmless for existing tests since none of them invoke `bundle` through it):

```bash
write_fake_brew() {
  cat > "$FAKE_BIN/brew" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "--prefix" ]; then
  echo "$BREW_PREFIX"
  exit 0
fi
if [ "\$1" = "install" ]; then
  echo "installed: \$2" >> "$BREW_PREFIX/installed.log"
  exit 0
fi
if [ "\$1" = "bundle" ]; then
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/brew"
}
```

Then change:

```bash
@test "install links clm into the brew prefix when brew and stow are present" {
  write_fake_brew
  write_fake_stow
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  [ "$status" -eq 0 ]
  [ -L "$BREW_PREFIX/bin/clm" ]
}
```

to:

```bash
@test "install links clm into the brew prefix when brew and stow are present" {
  write_fake_brew
  write_fake_stow
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  [ -L "$BREW_PREFIX/bin/clm" ]
}
```

and:

```bash
@test "install runs brew install stow when stow is missing" {
  write_fake_brew
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  [ "$status" -eq 0 ]
  grep -q "installed: stow" "$BREW_PREFIX/installed.log"
}
```

to:

```bash
@test "install runs brew install stow when stow is missing" {
  write_fake_brew
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  grep -q "installed: stow" "$BREW_PREFIX/installed.log"
}
```

and:

```bash
@test "install runs brew install gh when gh is missing" {
  write_fake_brew
  write_fake_stow
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  [ "$status" -eq 0 ]
  grep -q "installed: gh" "$BREW_PREFIX/installed.log"
}
```

to:

```bash
@test "install runs brew install gh when gh is missing" {
  write_fake_brew
  write_fake_stow
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  grep -q "installed: gh" "$BREW_PREFIX/installed.log"
}
```

(Leave `"install refuses when brew is missing and not confirmed"` and `"install invokes the configured install command..."` exactly as they are — they already don't depend on anything past `ensure_homebrew`/`ensure_gh`.)

- [ ] **Step 2: Write the failing tests for the new behavior**

Add a `write_fake_stow` upgrade (it currently just `exit 0`s, which is fine for tests that don't need real stowing — but the new end-to-end tests do need real stowing, so add a second helper rather than changing the existing one):

```bash
write_real_stow() {
  ln -sf "$(command -v stow)" "$FAKE_BIN/stow"
}
```

Append the rest to `tests/clm_install_test.bats`:

```bash

write_fake_gh() {
  local auth_status_exit="$1"
  cat > "$FAKE_BIN/gh" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "auth" ] && [ "\$2" = "status" ]; then
  exit $auth_status_exit
fi
if [ "\$1" = "auth" ] && [ "\$2" = "login" ]; then
  echo "login called" >> "$BREW_PREFIX/gh-login.log"
  exit 0
fi
if [ "\$1" = "repo" ] && [ "\$2" = "clone" ]; then
  echo "clone called: \$3 -> \$4" >> "$BREW_PREFIX/gh-clone.log"
  mkdir -p "\$4"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/gh"
}

@test "ensure_gh_auth skips gh auth login when already authenticated" {
  write_fake_brew
  write_fake_stow
  write_fake_gh 0
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  [ ! -e "$BREW_PREFIX/gh-login.log" ]
}

@test "ensure_gh_auth invokes gh auth login when not authenticated" {
  write_fake_brew
  write_fake_stow
  write_fake_gh 1
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  grep -q "login called" "$BREW_PREFIX/gh-login.log"
}

@test "ensure_cl_settings skips cloning when cl-settings already exists" {
  write_fake_brew
  write_fake_stow
  write_fake_gh 0
  mkdir -p "$CLM_ROOT/cl-settings"
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh" "someone/cl-settings"
  [ ! -e "$BREW_PREFIX/gh-clone.log" ]
}

@test "ensure_cl_settings clones when given a repo slug and cl-settings doesn't exist" {
  write_fake_brew
  write_fake_stow
  write_fake_gh 0
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh" "someone/cl-settings"
  grep -q "clone called: someone/cl-settings -> $CLM_ROOT/cl-settings" "$BREW_PREFIX/gh-clone.log"
}

@test "ensure_cl_settings skips gracefully with a helpful message when no slug is given" {
  write_fake_brew
  write_fake_stow
  write_fake_gh 0
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  [ ! -e "$BREW_PREFIX/gh-clone.log" ]
  [[ "$output" == *"skipping auto-clone"* ]]
}

@test "full bootstrap: install, auth, clone, and unpack succeed in one go" {
  write_fake_brew
  write_real_stow
  FAKE_UPSTREAM="$BATS_TEST_TMPDIR/fake-upstream/test-machine"
  mkdir -p "$FAKE_UPSTREAM/dotfiles/zsh" "$FAKE_UPSTREAM/vault/global/ssh/keys" "$FAKE_UPSTREAM/vault/bin" "$FAKE_UPSTREAM/pack"
  echo 'export FOO=1' > "$FAKE_UPSTREAM/dotfiles/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$FAKE_UPSTREAM/vault/bin/fix-perms.sh"
  chmod +x "$FAKE_UPSTREAM/vault/bin/fix-perms.sh"
  echo '# empty brewfile' > "$FAKE_UPSTREAM/pack/Brewfile"

  cat > "$FAKE_BIN/gh" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "auth" ] && [ "\$2" = "status" ]; then
  exit 0
fi
if [ "\$1" = "repo" ] && [ "\$2" = "clone" ]; then
  mkdir -p "\$4"
  cp -R "$BATS_TEST_TMPDIR/fake-upstream/." "\$4/"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/gh"

  run env PATH="$FAKE_BIN:/usr/bin:/bin" CLM_MACHINE_NAME="test-machine" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/clm-install.sh" "someone/cl-settings"
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew bundle complete"* ]]
  [ -L "$CLM_TARGET/.zshrc" ]
}

@test "resumability: running clm-install.sh a second time stays successful and doesn't redo auth or clone" {
  write_fake_brew
  write_real_stow
  FAKE_UPSTREAM="$BATS_TEST_TMPDIR/fake-upstream/test-machine"
  mkdir -p "$FAKE_UPSTREAM/dotfiles/zsh" "$FAKE_UPSTREAM/vault/global/ssh/keys" "$FAKE_UPSTREAM/vault/bin" "$FAKE_UPSTREAM/pack"
  echo 'export FOO=1' > "$FAKE_UPSTREAM/dotfiles/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$FAKE_UPSTREAM/vault/bin/fix-perms.sh"
  chmod +x "$FAKE_UPSTREAM/vault/bin/fix-perms.sh"

  cat > "$FAKE_BIN/gh" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "auth" ] && [ "\$2" = "status" ]; then
  exit 0
fi
if [ "\$1" = "auth" ] && [ "\$2" = "login" ]; then
  echo "login called" >> "$BREW_PREFIX/gh-login.log"
  exit 0
fi
if [ "\$1" = "repo" ] && [ "\$2" = "clone" ]; then
  echo "clone called" >> "$BREW_PREFIX/gh-clone.log"
  mkdir -p "\$4"
  cp -R "$BATS_TEST_TMPDIR/fake-upstream/." "\$4/"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/gh"

  env PATH="$FAKE_BIN:/usr/bin:/bin" CLM_MACHINE_NAME="test-machine" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/clm-install.sh" "someone/cl-settings"
  first_clone_calls="$(wc -l < "$BREW_PREFIX/gh-clone.log")"

  run env PATH="$FAKE_BIN:/usr/bin:/bin" CLM_MACHINE_NAME="test-machine" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/clm-install.sh" "someone/cl-settings"
  [ "$status" -eq 0 ]
  [ ! -e "$BREW_PREFIX/gh-login.log" ]
  second_clone_calls="$(wc -l < "$BREW_PREFIX/gh-clone.log")"
  [ "$first_clone_calls" -eq "$second_clone_calls" ]
}
```

- [ ] **Step 3: Run the tests to verify the new ones fail**

Run: `bats tests/clm_install_test.bats`
Expected: the 7 new tests FAIL (no `ensure_gh_auth`/`ensure_cl_settings`/final `clm unpack` call exist yet); the 5 pre-existing (adjusted) tests still PASS unchanged, since they don't depend on the new code paths.

- [ ] **Step 4: Implement the new functions and wire them into `main()` in `clm-install.sh`**

Add after `ensure_gh`:

```bash
ensure_gh_auth() {
  if gh auth status >/dev/null 2>&1; then
    echo "gh: already authenticated"
    return
  fi
  gh auth login
}

ensure_cl_settings() {
  local repo_slug="$1"
  local cl_settings_root="$CLM_ROOT/cl-settings"
  if [ -d "$cl_settings_root" ]; then
    echo "cl-settings: found at $cl_settings_root"
    return
  fi
  if [ -z "$repo_slug" ]; then
    echo "cl-settings not found and no repo slug given — skipping auto-clone"
    return
  fi
  gh repo clone "$repo_slug" "$cl_settings_root"
}
```

Replace `main()`:

```bash
main() {
  local settings_repo="${1:-}"
  ensure_homebrew
  ensure_stow
  ensure_gh
  link_clm_cli
  ensure_gh_auth
  ensure_cl_settings "$settings_repo"
  "$CLM_ROOT/bin/clm" unpack
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bats tests/clm_install_test.bats`
Expected: `12 tests, 0 failures`

- [ ] **Step 6: Run the full suite to confirm no regressions**

Run: `bats tests/`
Expected: 0 failures.

- [ ] **Step 7: Commit**

```bash
git add clm-install.sh tests/clm_install_test.bats
git commit -m "clm-install.sh: full one-command resumable bootstrap (auth, clone, unpack)"
```

---

## Task 2: README update

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the `## First-time setup on a new machine` section**

```markdown
## First-time setup on a new machine

    git clone <clm-engine-repo-url> ~/clm
    cd ~/clm && ./clm-install.sh <you>/cl-settings

That's the whole flow: Homebrew, Stow, and `gh` get installed if missing,
`gh auth login` runs if you're not already authenticated (browser-based —
no SSH key needed), `cl-settings` gets cloned if it isn't already present,
and `clm unpack` runs at the end (stow onboard + vault fix-perms + brew
bundle). Every step checks its own precondition first, so if this gets
interrupted partway (network blip, closed terminal mid-`gh auth login`),
just run the same command again — nothing gets redone unnecessarily, and
it picks up wherever it left off.

If you don't have the repo slug handy yet, `./clm-install.sh` (no argument)
still installs Homebrew/Stow/gh and authenticates `gh`; it stops with a
clear message at the `cl-settings not found` step, telling you exactly
what to run once you do have it.
```

- [ ] **Step 2: Run the full test suite one more time**

Run: `bats tests/`
Expected: all tests pass, `0 failures`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document the one-command resumable bootstrap flow"
```
