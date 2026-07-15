# cl-settings Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate dotfiles + vault + pack into one `cl-settings` repo nested under `~/clm`, add `gh` to the bootstrap, and add `clm unpack` to rehydrate a machine from it — per `docs/superpowers/specs/2026-07-15-clm-settings-consolidation-design.md`.

**Architecture:** New env vars `CLM_MACHINE_NAME`/`CLM_SETTINGS_DIR`/`CLM_DOTFILES_DIR` computed in `lib/clm/common.sh` and exported by `bin/clm`. `stow.sh` repointed from `CLM_ROOT` to `CLM_DOTFILES_DIR`. `vault.sh`/`pack.sh` defaults repointed to `CLM_SETTINGS_DIR`. New `lib/clm/unpack.sh`. Real repo content migrated into the new layout.

**Tech Stack:** Bash (bash 3.2 compatible), GNU Stow, `scutil` (macOS machine name), bats-core.

## Global Constraints

- Same bash 3.2 compatibility constraints as prior plans.
- Tests always pass `CLM_DOTFILES_DIR`/`CLM_VAULT`/`CLM_PACK_DIR` explicitly rather than relying on real `scutil`/machine-name-dependent defaults, so they stay deterministic — except for a small number of dedicated tests whose entire point is to verify the default-computation logic itself.
- Task 6 (real content migration) operates on the actual live repo. Verify with `git status`/`git diff` before and after each destructive-looking step; nothing here is unrecoverable since the old content stays in this repo's git history even after being moved.

---

## Task 1: `common.sh` — machine name, `CLM_SETTINGS_DIR`, `CLM_DOTFILES_DIR`

**Files:**
- Modify: `lib/clm/common.sh`
- Modify: `tests/common_test.bats`

**Interfaces:**
- Produces: `clm::machine_name()` — echoes `$CLM_MACHINE_NAME` if set, else `scutil --get ComputerName`. `CLM_MACHINE_NAME`, `CLM_SETTINGS_DIR` (default `$CLM_ROOT/cl-settings/$CLM_MACHINE_NAME`), `CLM_DOTFILES_DIR` (default `$CLM_SETTINGS_DIR/dotfiles`) as new variables. `CLM_VAULT`'s default changes from `$CLM_ROOT/vault` to `$CLM_SETTINGS_DIR/vault`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/common_test.bats`:

```bash

@test "machine_name respects CLM_MACHINE_NAME override" {
  run bash -c "
    export CLM_MACHINE_NAME='test-machine'
    source '$CLM_ROOT/lib/clm/common.sh'
    clm::machine_name
  "
  [ "$status" -eq 0 ]
  [ "$output" = "test-machine" ]
}

@test "CLM_SETTINGS_DIR, CLM_DOTFILES_DIR, and CLM_VAULT default from CLM_ROOT and machine name" {
  run bash -c "
    export CLM_ROOT='/tmp/fake-clm-root'
    export CLM_MACHINE_NAME='test-machine'
    source '$CLM_ROOT/lib/clm/common.sh'
    echo \"\$CLM_SETTINGS_DIR\"
    echo \"\$CLM_DOTFILES_DIR\"
    echo \"\$CLM_VAULT\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/fake-clm-root/cl-settings/test-machine"* ]]
  [[ "$output" == *"/tmp/fake-clm-root/cl-settings/test-machine/dotfiles"* ]]
  [[ "$output" == *"/tmp/fake-clm-root/cl-settings/test-machine/vault"* ]]
}

@test "explicit CLM_SETTINGS_DIR override takes precedence over the computed default" {
  run bash -c "
    export CLM_ROOT='/tmp/fake-clm-root'
    export CLM_MACHINE_NAME='test-machine'
    export CLM_SETTINGS_DIR='/tmp/custom-settings'
    source '$CLM_ROOT/lib/clm/common.sh'
    echo \"\$CLM_DOTFILES_DIR\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/custom-settings/dotfiles" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/common_test.bats`
Expected: FAIL — `clm::machine_name`, `CLM_SETTINGS_DIR`, `CLM_DOTFILES_DIR` don't exist yet.

- [ ] **Step 3: Rewrite `lib/clm/common.sh`**

```bash
#!/usr/bin/env bash

CLM_TARGET="${CLM_TARGET:-$HOME}"

clm::machine_name() {
  echo "${CLM_MACHINE_NAME:-$(scutil --get ComputerName)}"
}

CLM_MACHINE_NAME="$(clm::machine_name)"
CLM_SETTINGS_DIR="${CLM_SETTINGS_DIR:-${CLM_ROOT:-.}/cl-settings/$CLM_MACHINE_NAME}"
CLM_DOTFILES_DIR="${CLM_DOTFILES_DIR:-$CLM_SETTINGS_DIR/dotfiles}"
CLM_VAULT="${CLM_VAULT:-$CLM_SETTINGS_DIR/vault}"

clm::die() {
  echo "clm: $*" >&2
  exit 1
}

clm::confirm() {
  local prompt="$1" reply
  if [ "${CLM_YES:-0}" = "1" ]; then
    return 0
  fi
  read -r -p "$prompt " reply
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/common_test.bats`
Expected: `8 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/clm/common.sh tests/common_test.bats
git commit -m "Add machine_name, CLM_SETTINGS_DIR, CLM_DOTFILES_DIR; repoint CLM_VAULT default"
```

---

## Task 2: Repoint `stow.sh` to `CLM_DOTFILES_DIR`; update `bin/clm` exports

**Files:**
- Modify: `lib/clm/stow.sh`
- Modify: `bin/clm`
- Modify: `tests/test_helper.bash`
- Modify: `tests/stow_test.bats`
- Modify: `tests/status_test.bats`
- Modify: `tests/dispatch_test.bats`
- Modify: `tests/ssh_package_test.bats`

**Interfaces:**
- Consumes: `CLM_DOTFILES_DIR` (Task 1).
- No function signature changes — `clm::stow_packages`, `clm::is_stowed`, `clm::validate_package`, `cmd_stow_add/remove/onboard/list` keep the same names, just read from `$CLM_DOTFILES_DIR` instead of `$CLM_ROOT`. The `CLM_STOW_EXCLUDE` mechanism is removed — under the new layout, `vault`/`pack` are siblings of `dotfiles/`, not children of it, so there's structurally nothing left to exclude.

- [ ] **Step 1: Update `tests/test_helper.bash` to provide `CLM_DOTFILES_DIR`**

```bash
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
```

- [ ] **Step 2: Update the four affected test files to use `$CLM_DOTFILES_DIR`**

In `tests/stow_test.bats`, change the `setup()` block and remove the two tests whose premise no longer applies (vault is structurally unreachable from `CLM_DOTFILES_DIR` now, so there's nothing left to special-case):

```bash
setup() {
  setup_clm_env
  mkdir -p "$CLM_DOTFILES_DIR/zsh"
  echo 'export FOO=1' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
}
```

Delete the `"stow_packages lists zsh but excludes vault, bin, lib, docs"` test and the `"cmd_stow_add refuses to treat vault as a package"` test entirely (both reference `$CLM_ROOT/vault`/`$CLM_ROOT/docs`, which no longer relate to how `CLM_DOTFILES_DIR` works). Everywhere else in the file, replace `$CLM_ROOT/zsh` with `$CLM_DOTFILES_DIR/zsh` (there are no other `$CLM_ROOT/vault` etc. references left after those two tests are removed — verify with `grep -n CLM_ROOT tests/stow_test.bats` after editing; only `CLM_ROOT=` env-var-passthrough lines for `bash -c` invocations should remain).

In `tests/status_test.bats`, in `setup()`:

```bash
setup() {
  setup_clm_env
  mkdir -p "$CLM_DOTFILES_DIR/zsh"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
}
```

In `tests/dispatch_test.bats`, in `setup()`:

```bash
setup() {
  setup_clm_env
  mkdir -p "$CLM_DOTFILES_DIR/zsh"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
}
```

And add `CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR"` to every `env ...` invocation of `"$CLM_ROOT/bin/clm"` in that file (five call sites) — e.g. the first becomes:

```bash
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" "$CLM_ROOT/bin/clm"
```

Apply the same `CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR"` addition to the other four `env ...` calls in that file (unknown noun, unknown verb, stow add, `--yes` test, and the symlink-resolution test — the last one already builds its own `env` invocation with `CLM_TARGET` only, add `CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR"` there too since it doesn't set `CLM_ROOT` — the symlink test relies on `bin/clm` resolving `CLM_ROOT` itself, but `CLM_DOTFILES_DIR` still needs to be passed explicitly since it isn't derived from symlink resolution).

In `tests/ssh_package_test.bats`, in `setup()`:

```bash
setup() {
  setup_clm_env
  mkdir -p "$CLM_DOTFILES_DIR/ssh/.ssh"
  cp "$BATS_TEST_DIRNAME/../ssh/.ssh/config" "$CLM_DOTFILES_DIR/ssh/.ssh/config"
}
```

And add `CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR"` to the two `env` invocations in that file's tests.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bats tests/stow_test.bats tests/status_test.bats tests/dispatch_test.bats tests/ssh_package_test.bats`
Expected: FAIL — `stow.sh` still reads `$CLM_ROOT`, so packages created under `$CLM_DOTFILES_DIR` aren't found.

- [ ] **Step 4: Rewrite `lib/clm/stow.sh`**

```bash
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
```

- [ ] **Step 5: Update `bin/clm` to export the new variables**

Replace the variable-setup block:

```bash
CLM_ROOT="${CLM_ROOT:-$(resolve_root)}"
export CLM_ROOT
CLM_TARGET="${CLM_TARGET:-$HOME}"
export CLM_TARGET
CLM_VAULT="${CLM_VAULT:-$CLM_ROOT/vault}"
export CLM_VAULT
```

with:

```bash
CLM_ROOT="${CLM_ROOT:-$(resolve_root)}"
export CLM_ROOT
CLM_TARGET="${CLM_TARGET:-$HOME}"
export CLM_TARGET
CLM_MACHINE_NAME="${CLM_MACHINE_NAME:-$(scutil --get ComputerName)}"
export CLM_MACHINE_NAME
CLM_SETTINGS_DIR="${CLM_SETTINGS_DIR:-$CLM_ROOT/cl-settings/$CLM_MACHINE_NAME}"
export CLM_SETTINGS_DIR
CLM_DOTFILES_DIR="${CLM_DOTFILES_DIR:-$CLM_SETTINGS_DIR/dotfiles}"
export CLM_DOTFILES_DIR
CLM_VAULT="${CLM_VAULT:-$CLM_SETTINGS_DIR/vault}"
export CLM_VAULT
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bats tests/stow_test.bats tests/status_test.bats tests/dispatch_test.bats tests/ssh_package_test.bats`
Expected: all pass (stow_test.bats now has 8 tests after the 2 removals, others unchanged in count).

- [ ] **Step 7: Run the full suite to confirm no regressions**

Run: `bats tests/`
Expected: 0 failures (count will be down by 2 from the deleted stow tests, up by 3 from Task 1 — net +1 from before this task).

- [ ] **Step 8: Commit**

```bash
git add lib/clm/stow.sh bin/clm tests/test_helper.bash tests/stow_test.bats tests/status_test.bats tests/dispatch_test.bats tests/ssh_package_test.bats
git commit -m "Repoint stow.sh at CLM_DOTFILES_DIR; remove now-structural vault exclusion"
```

---

## Task 3: Repoint `pack.sh`'s `CLM_PACK_DIR` default to `CLM_SETTINGS_DIR`

**Files:**
- Modify: `lib/clm/pack.sh`
- Modify: `tests/pack_test.bats`

**Interfaces:**
- `CLM_PACK_DIR`'s default changes from `$CLM_ROOT/pack` to `$CLM_SETTINGS_DIR/pack`. No other logic changes — existing `pack_test.bats`/`pack_dispatch_test.bats` tests already override `CLM_PACK_DIR` explicitly and are unaffected.

- [ ] **Step 1: Write the failing test**

Append to `tests/pack_test.bats`:

```bash

@test "CLM_PACK_DIR defaults from CLM_SETTINGS_DIR when not explicitly set" {
  run bash -c "
    export CLM_ROOT='/tmp/fake-clm-root'
    export CLM_MACHINE_NAME='test-machine'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/pack.sh'
    echo \"\$CLM_PACK_DIR\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/fake-clm-root/cl-settings/test-machine/pack" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/pack_test.bats`
Expected: FAIL — `CLM_PACK_DIR` still defaults to `$CLM_ROOT/pack`.

- [ ] **Step 3: Update `lib/clm/pack.sh`**

Change the top of the file:

```bash
CLM_PACK_DIR="${CLM_PACK_DIR:-$CLM_ROOT/pack}"
CLM_BACKUP_DIR="${CLM_BACKUP_DIR:-$HOME/clm-backups}"
```

to:

```bash
CLM_PACK_DIR="${CLM_PACK_DIR:-$CLM_SETTINGS_DIR/pack}"
CLM_BACKUP_DIR="${CLM_BACKUP_DIR:-$HOME/clm-backups}"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/pack_test.bats tests/pack_dispatch_test.bats`
Expected: 0 failures (existing tests unaffected since they override `CLM_PACK_DIR` explicitly; new test passes).

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `bats tests/`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/clm/pack.sh tests/pack_test.bats
git commit -m "Repoint CLM_PACK_DIR default at CLM_SETTINGS_DIR"
```

---

## Task 4: `clm-install.sh` also installs `gh`

**Files:**
- Modify: `clm-install.sh`
- Modify: `tests/clm_install_test.bats`

**Interfaces:**
- Produces: `ensure_gh()`, mirroring `ensure_stow()`.

- [ ] **Step 1: Write the failing test**

Append to `tests/clm_install_test.bats`:

```bash

@test "install runs brew install gh when gh is missing" {
  write_fake_brew
  write_fake_stow
  run env PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/clm-install.sh"
  [ "$status" -eq 0 ]
  grep -q "installed: gh" "$BREW_PREFIX/installed.log"
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/clm_install_test.bats`
Expected: FAIL — `clm-install.sh` doesn't check for `gh` yet.

- [ ] **Step 3: Update `clm-install.sh`**

Add a new function after `ensure_stow`:

```bash
ensure_gh() {
  if command -v gh >/dev/null 2>&1; then
    echo "gh: found"
    return
  fi
  echo "gh not found, installing via Homebrew..."
  brew install gh
}
```

Update `main()`:

```bash
main() {
  ensure_homebrew
  ensure_stow
  ensure_gh
  link_clm_cli
  cat <<EOF

Done. 'clm' is now on your PATH.

Next steps:
  gh auth login
  gh repo clone <you>/cl-settings $CLM_SETTINGS_DIR
  clm unpack
EOF
}
```

(Note: `$CLM_SETTINGS_DIR` is already exported by the variable-setup block at the top of `clm-install.sh` once Task 1/2's `common.sh` changes are sourced — no additional export needed here since `clm-install.sh` already sources `common.sh`.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/clm_install_test.bats`
Expected: `6 tests, 0 failures`

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `bats tests/`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add clm-install.sh tests/clm_install_test.bats
git commit -m "clm-install.sh also ensures gh is installed"
```

---

## Task 5: `clm unpack`

**Files:**
- Create: `lib/clm/unpack.sh`
- Modify: `bin/clm` (source it, add `unpack` noun, update usage)
- Create: `tests/unpack_test.bats`

**Interfaces:**
- Consumes: `CLM_SETTINGS_DIR`, `cmd_stow_onboard`, `cmd_vault_fix_perms`.
- Produces: `cmd_unpack()`.

- [ ] **Step 1: Write the failing tests**

Create `tests/unpack_test.bats`:

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
}

@test "clm unpack refuses when cl-settings is not present" {
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$CLM_ROOT/does-not-exist" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -ne 0 ]
  [[ "$output" == *"cl-settings not found"* ]]
}

@test "clm unpack stows dotfiles, fixes vault perms, and reports no Brewfile when absent" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  mkdir -p "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  cp "$BATS_TEST_DIRNAME/../vault/bin/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  [ -L "$CLM_TARGET/.zshrc" ]
  [[ "$output" == *"skipping CLI tools/apps install"* ]]
}

@test "clm unpack runs brew bundle when a Brewfile is present" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  mkdir -p "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  cp "$BATS_TEST_DIRNAME/../vault/bin/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"
  echo '# empty brewfile' > "$settings_dir/pack/Brewfile"
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  cat > "$FAKE_BIN/brew" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "bundle" ]; then
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/brew"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew bundle complete"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/unpack_test.bats`
Expected: FAIL — `clm` doesn't recognize the `unpack` noun yet.

- [ ] **Step 3: Implement `lib/clm/unpack.sh`**

```bash
#!/usr/bin/env bash

cmd_unpack() {
  [ -d "$CLM_SETTINGS_DIR" ] || clm::die "cl-settings not found at $CLM_SETTINGS_DIR (clone it first: gh repo clone <you>/cl-settings $CLM_SETTINGS_DIR)"
  cmd_stow_onboard
  cmd_vault_fix_perms
  if [ -f "$CLM_SETTINGS_DIR/pack/Brewfile" ]; then
    brew bundle --file="$CLM_SETTINGS_DIR/pack/Brewfile" || clm::die "brew bundle failed"
    echo "brew bundle complete"
  else
    echo "no Brewfile found at $CLM_SETTINGS_DIR/pack/Brewfile — skipping CLI tools/apps install"
  fi
}
```

- [ ] **Step 4: Wire `unpack` into `bin/clm`**

Add to the source block:

```bash
# shellcheck source=lib/clm/unpack.sh
source "$CLM_ROOT/lib/clm/unpack.sh"
```

Update `usage()`:

```bash
usage() {
  cat <<'EOF'
Usage: clm <noun> <verb> [args] [--yes]

Nouns:
  stow    onboard | add <pkg> | remove <pkg> | list
  vault   fix-perms
  status
  pack    list | all | brew | mas | vscode | cursor | npm | pnpm
  unpack
EOF
}
```

Add to the `case "$noun" in ... esac` block:

```bash
    unpack) cmd_unpack ;;
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bats tests/unpack_test.bats`
Expected: `3 tests, 0 failures`

- [ ] **Step 6: Run the full suite to confirm no regressions**

Run: `bats tests/`
Expected: 0 failures.

- [ ] **Step 7: Commit**

```bash
git add lib/clm/unpack.sh bin/clm tests/unpack_test.bats
git commit -m "Add clm unpack: stow onboard + vault fix-perms + brew bundle"
```

---

## Task 6: Migrate real repo content into the new layout

**Files:**
- Move: `zsh/`, `bash/`, `git/`, `ssh/` → `cl-settings/<machine>/dotfiles/`
- Move: `vault/`'s contents (not its `.git`) → `cl-settings/<machine>/vault/`
- Move: `pack/`'s existing real contents (if any) → `cl-settings/<machine>/pack/`
- Modify: `.gitignore`
- Create: `cl-settings/` as a fresh, independent git repo

This task is a real migration on the live repo, not a TDD cycle — there's no new behavior to unit test, just a file reorganization. Verify with the full test suite (which by this point only depends on the env-var contract, not real paths) plus a manual smoke check.

- [ ] **Step 1: Capture the real machine name and confirm current state**

```bash
cd ~/machine-setup
MACHINE="$(scutil --get ComputerName)"
echo "$MACHINE"
git status --short
ls vault
```

Expected: `MACHINE` prints a non-empty computer name; `git status --short` shows a clean tree (or only the untracked real `pack/` files from earlier manual testing); `vault` lists its existing skeleton (`README.md`, `global/`, `projects/`, `bin/`).

- [ ] **Step 2: Create the new nested structure and move dotfiles + vault**

```bash
mkdir -p "cl-settings/$MACHINE/dotfiles" "cl-settings/$MACHINE/vault" "cl-settings/$MACHINE/pack"
mv zsh bash git ssh "cl-settings/$MACHINE/dotfiles/"
for entry in vault/*; do
  cp -R "$entry" "cl-settings/$MACHINE/vault/"
done
rm -rf vault
```

- [ ] **Step 3: Move any existing real pack output**

```bash
if [ -d pack ] && [ -n "$(ls -A pack 2>/dev/null)" ]; then
  for entry in pack/*; do
    mv "$entry" "cl-settings/$MACHINE/pack/"
  done
fi
rm -rf pack
```

- [ ] **Step 4: Verify the move**

```bash
find "cl-settings/$MACHINE" -maxdepth 3
```

Expected: `dotfiles/{zsh,bash,git,ssh}`, `vault/{README.md,global,projects,bin}`, and (if pack output existed) `pack/{Brewfile,mas.txt,...}`.

- [ ] **Step 5: Update `.gitignore`**

Replace its contents (it previously had `vault/`, `pack/`, `.DS_Store` — both of the first two no longer apply at the repo root):

```
cl-settings/
.DS_Store
```

- [ ] **Step 6: Initialize `cl-settings` as its own git repo**

```bash
cd "cl-settings/$MACHINE/.." # i.e. cd cl-settings
git init -q
git add -A
git commit -q -m "Initial cl-settings: migrate dotfiles + vault for $MACHINE"
cd ../..
```

(Run `cd ~/machine-setup` afterward, or use absolute paths, to make sure subsequent steps run from the outer repo root.)

- [ ] **Step 7: Run the full test suite**

```bash
cd ~/machine-setup
bats tests/
```

Expected: 0 failures — the suite doesn't depend on real repo-root paths, only on the env-var contract established in Tasks 1-5, so this migration shouldn't affect it. This is the verification step for this non-TDD task.

- [ ] **Step 8: Manual smoke check with the real `clm` binary**

```bash
clm status
```

Expected: reports each dotfiles package's stow state (whatever it currently is on this real machine) and vault presence — confirms the real `CLM_SETTINGS_DIR`/`CLM_DOTFILES_DIR`/`CLM_VAULT` defaults resolve correctly against the newly-migrated real content.

- [ ] **Step 9: Commit the outer repo's changes**

```bash
git add -A
git status --short
git commit -m "Move dotfiles/vault/pack into cl-settings/<machine>/; retire standalone vault/ repo"
```

---

## Task 7: README overhaul and final verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite the relevant sections of `README.md`**

Replace `## First-time setup on a new machine`:

```markdown
## First-time setup on a new machine

    git clone <clm-engine-repo-url> ~/clm
    cd ~/clm && ./clm-install.sh
    gh auth login
    gh repo clone <you>/cl-settings ~/clm/cl-settings
    clm unpack
```

Replace `## Layout`:

```markdown
## Layout

- `bin/clm` — the CLI. `lib/clm/*.sh` holds one module per noun. This repo
  is the engine only — no personal data lives here.
- `clm-install.sh` — one-time bootstrap (Homebrew, Stow, gh, puts `clm` on PATH).
- `cl-settings/` — a separate, private, gitignored nested git repo holding
  your actual settings, namespaced per machine:
  `cl-settings/<machine-name>/{dotfiles,vault,pack}`. Clone it independently
  via `gh repo clone`; it's never part of this repo's history.
```

Replace the `## \`clm\` commands` code block:

```markdown
    clm stow onboard          # stow zsh, bash, git, ssh in one shot
    clm stow add <package>    # stow one package
    clm stow remove <package> # unstow one package (asks for confirmation)
    clm stow list             # show stow state of every package
    clm vault fix-perms       # fix key file/dir permissions in cl-settings/<machine>/vault
    clm status                # stow + vault health check
    clm pack list              # show which pack checkers are available here
    clm pack all                # capture everything available, then archive the whole ~/clm tree
    clm pack <checker>          # capture one source, e.g. `clm pack brew`
    clm unpack                   # stow onboard + vault fix-perms + brew bundle, from cl-settings
```

In `## What's not here yet`, replace the first bullet (restoring is now partially done):

```markdown
## What's not here yet

- `clm unpack` only restores dotfiles, vault, and brew (CLI tools + apps).
  Restoring VS Code/Cursor extensions or npm/pnpm globals from their pack
  files is still manual.
- Vaulting tool-managed auth (`gh`, `vercel`, `npm login`, Docker registry).
- Per-project "active project" switching for single-file configs (`.npmrc`,
  `.env`, docker-compose) — the planned project hub, a future `clm project`
  namespace.
```

Update the final "See also" line to include the new spec:

```markdown
See `docs/superpowers/specs/2026-07-15-clm-foundation-design.md`,
`docs/superpowers/specs/2026-07-15-clm-pack-design.md`, and
`docs/superpowers/specs/2026-07-15-clm-settings-consolidation-design.md`
for the full design rationale.
```

- [ ] **Step 2: Run the full test suite one more time**

Run: `bats tests/`
Expected: all tests pass, `0 failures`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document cl-settings consolidation and clm unpack in the README"
```
