# One-Line curl Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A single `curl ... | sh` command that bootstraps a brand-new machine end to end, per the user's request for a one-line install command (the `clm` repo is public, so `raw.githubusercontent.com` can serve the script with no auth; git is assumed already present on the machine).

**Architecture:** A new `bootstrap.sh` at the repo root, fetched and piped to `sh`. It clones `~/clm` (skipping if already present) and then `exec`s the existing `clm-install.sh` with the `cl-settings` repo slug forwarded as `$1`, handing off to the flow already built (Homebrew/Stow/gh, auth, cl-settings clone, `clm unpack`).

**Tech Stack:** POSIX `sh` (not bash — this script is invoked via `sh -s --`, so it must not use bash-only syntax), bats-core for testing.

## Global Constraints

- `bootstrap.sh` must be portable POSIX `sh`, not bash — no `[[ ]]`, no arrays, no bash-only parameter expansions beyond `${VAR:-default}` (which is POSIX).
- The clone target defaults to `$HOME/clm`, overridable via `CLM_BOOTSTRAP_DIR` (mirroring the rest of the codebase's `CLM_*` override pattern) so tests never touch the real `$HOME`.
- Tests fake `git` and stub `clm-install.sh` itself — never perform a real clone or a real install.

---

## Task 1: `bootstrap.sh`

**Files:**
- Create: `bootstrap.sh`
- Create: `tests/bootstrap_test.bats`

**Interfaces:**
- Produces: a script taking the `cl-settings` repo slug as `$1`. Clones `https://github.com/thucxuong/clm.git` into `${CLM_BOOTSTRAP_DIR:-$HOME/clm}` if that directory doesn't already exist, then `exec`s `<that-dir>/clm-install.sh "$1"`.

- [ ] **Step 1: Write the failing tests**

Create `tests/bootstrap_test.bats`:

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  CLM_BOOTSTRAP_DIR="$BATS_TEST_TMPDIR/clm"
}

write_fake_git() {
  cat > "$FAKE_BIN/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "clone" ]; then
  echo "clone: \$2 -> \$3" >> "$BATS_TEST_TMPDIR/git-calls.log"
  mkdir -p "\$3"
  printf '#!/usr/bin/env bash\necho "clm-install.sh called with: \$1"\n' > "\$3/clm-install.sh"
  chmod +x "\$3/clm-install.sh"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/git"
}

@test "bootstrap.sh clones clm when not already present" {
  write_fake_git
  run env PATH="$FAKE_BIN:/usr/bin:/bin" CLM_BOOTSTRAP_DIR="$CLM_BOOTSTRAP_DIR" sh "$BATS_TEST_DIRNAME/../bootstrap.sh" "someone/cl-settings"
  [ "$status" -eq 0 ]
  grep -q "clone: https://github.com/thucxuong/clm.git -> $CLM_BOOTSTRAP_DIR" "$BATS_TEST_TMPDIR/git-calls.log"
}

@test "bootstrap.sh skips cloning when the target directory already exists" {
  write_fake_git
  mkdir -p "$CLM_BOOTSTRAP_DIR"
  cat > "$CLM_BOOTSTRAP_DIR/clm-install.sh" <<'EOF'
#!/usr/bin/env bash
echo "clm-install.sh called with: $1"
EOF
  chmod +x "$CLM_BOOTSTRAP_DIR/clm-install.sh"

  run env PATH="$FAKE_BIN:/usr/bin:/bin" CLM_BOOTSTRAP_DIR="$CLM_BOOTSTRAP_DIR" sh "$BATS_TEST_DIRNAME/../bootstrap.sh" "someone/cl-settings"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/git-calls.log" ]
}

@test "bootstrap.sh execs clm-install.sh with the repo slug forwarded" {
  write_fake_git
  run env PATH="$FAKE_BIN:/usr/bin:/bin" CLM_BOOTSTRAP_DIR="$CLM_BOOTSTRAP_DIR" sh "$BATS_TEST_DIRNAME/../bootstrap.sh" "someone/cl-settings"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clm-install.sh called with: someone/cl-settings"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/bootstrap_test.bats`
Expected: FAIL — `bootstrap.sh` doesn't exist yet.

- [ ] **Step 3: Implement `bootstrap.sh`**

```sh
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
```

- [ ] **Step 4: Make it executable and run the tests**

Run: `chmod +x bootstrap.sh && bats tests/bootstrap_test.bats`
Expected: `3 tests, 0 failures`

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `bats tests/`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add bootstrap.sh tests/bootstrap_test.bats
git commit -m "Add bootstrap.sh for a one-line curl-based install"
```

---

## Task 2: README update

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add the one-liner as the primary documented setup method**

Replace `## First-time setup on a new machine`'s opening code block and lead-in:

```markdown
## First-time setup on a new machine

    curl -fsSL https://raw.githubusercontent.com/thucxuong/clm/main/bootstrap.sh | sh -s -- thucxuong/cl-settings

That's it — one command. It clones `~/clm`, then hands off to
`clm-install.sh` (Homebrew, Stow, gh, `gh auth login`, clones
`cl-settings`, runs `clm unpack`). Every step still checks its own
precondition, so it's safe to run again if interrupted.

Prefer to inspect before piping to `sh`? The equivalent two-step version:

    git clone https://github.com/thucxuong/clm.git ~/clm
    cd ~/clm && ./clm-install.sh thucxuong/cl-settings
```

- [ ] **Step 2: Run the full test suite one more time**

Run: `bats tests/`
Expected: all tests pass, `0 failures`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document the one-line curl bootstrap"
```
