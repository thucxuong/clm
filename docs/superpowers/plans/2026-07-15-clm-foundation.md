# CLM Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `~/clm` foundation — Stow-managed dotfiles, a private `vault/` secrets tree, and a `clm` CLI that wraps both behind a small, safe command surface — as specified in `docs/superpowers/specs/2026-07-15-clm-foundation-design.md`.

**Architecture:** A single git repo (this one, `~/machine-setup`, to be renamed `~/clm` by the user after this plan lands) holds Stow packages at its root and a `bin/clm` bash dispatcher backed by small `lib/clm/*.sh` modules (one per noun: `stow`, `vault`, `status`, plus a shared `common.sh` for safety primitives). A nested, separately-git-tracked `vault/` directory holds SSH keys/config, gitignored by the outer repo. `clm-install.sh` bootstraps Homebrew/Stow and symlinks `clm` onto `PATH`.

**Tech Stack:** Bash (must run under bash 3.2, macOS's system default), GNU Stow, bats-core for testing.

## Global Constraints

- Must run correctly under bash 3.2.57 (macOS system default) — no associative arrays, no `mapfile`/`readarray`, no `set -u` combined with possibly-empty array expansion, no `${var,,}` case conversion. Use plain `set -e` (no `-u`).
- GNU Stow is the only external dependency for the dotfiles mechanism; `clm-install.sh` installs it via Homebrew if missing.
- bats-core is the test runner for all shell script logic (`brew install bats-core`).
- Every automated task/test in this plan operates against temporary directories via `CLM_ROOT`/`CLM_TARGET`/`CLM_VAULT` environment overrides — **never** against the real `$HOME`, the real `~/dotfiles`, or the real Homebrew prefix. Actually cutting the live machine over (renaming this repo to `~/clm`, running `clm-install.sh` for real, running `clm stow onboard` against real `$HOME`) is a manual step the user performs themselves after this plan completes — it is intentionally not automated by any task here.
- `vault/` ships in this plan as an empty skeleton with placeholder/template content only — no real SSH keys are created or migrated.
- `vault` and `bin` are never treated as stowable packages, under any circumstance.

---

## Task 1: Repo scaffolding, bats harness, and the safety-layer primitives

**Files:**
- Create: `.gitignore`
- Create: `lib/clm/common.sh`
- Create: `tests/test_helper.bash`
- Create: `tests/common_test.bats`

**Interfaces:**
- Produces: `clm::die(message)` — prints `clm: <message>` to stderr, exits 1.
- Produces: `clm::confirm(prompt)` — returns 0 (confirmed) if `CLM_YES=1` is set in the environment, otherwise reads one line from stdin and returns 0 only for `y`/`Y`/`yes`/`YES`.
- Produces: `setup_clm_env` (test helper) — sets `CLM_ROOT`/`CLM_TARGET`/`CLM_VAULT` to fresh temp dirs under `BATS_TEST_TMPDIR`, copies `bin/clm` and `lib/clm/*.sh` into the temp `CLM_ROOT`. Later test files reuse this via `load 'test_helper'`.

- [ ] **Step 1: Install bats-core**

Run: `brew install bats-core`
Expected: installs successfully; `bats --version` prints a version string.

- [ ] **Step 2: Create `.gitignore`**

```
vault/
.DS_Store
```

- [ ] **Step 3: Write the failing test for `clm::die` and `clm::confirm`**

Create `tests/common_test.bats`:

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
}

@test "die prints a prefixed message to stderr and exits 1" {
  run bash -c "source '$CLM_ROOT/lib/clm/common.sh'; clm::die 'boom'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"clm: boom"* ]]
}

@test "confirm bypasses the prompt when CLM_YES=1" {
  run bash -c "export CLM_YES=1; source '$CLM_ROOT/lib/clm/common.sh'; clm::confirm 'proceed?'"
  [ "$status" -eq 0 ]
}

@test "confirm returns success on a piped y" {
  run bash -c "source '$CLM_ROOT/lib/clm/common.sh'; echo y | clm::confirm 'proceed?'"
  [ "$status" -eq 0 ]
}

@test "confirm returns failure on a piped n" {
  run bash -c "source '$CLM_ROOT/lib/clm/common.sh'; echo n | clm::confirm 'proceed?'"
  [ "$status" -eq 1 ]
}

@test "confirm returns failure on empty input" {
  run bash -c "source '$CLM_ROOT/lib/clm/common.sh'; echo '' | clm::confirm 'proceed?'"
  [ "$status" -eq 1 ]
}
```

Create `tests/test_helper.bash` (needed for `common_test.bats` to even load, but `lib/clm/common.sh` doesn't exist yet — that's the point, this fails first):

```bash
setup_clm_env() {
  CLM_ROOT="$BATS_TEST_TMPDIR/clm-root"
  CLM_TARGET="$BATS_TEST_TMPDIR/home"
  CLM_VAULT="$CLM_ROOT/vault"
  export CLM_ROOT CLM_TARGET CLM_VAULT
  mkdir -p "$CLM_ROOT/bin" "$CLM_ROOT/lib/clm" "$CLM_TARGET"
  cp "$BATS_TEST_DIRNAME/../bin/clm" "$CLM_ROOT/bin/clm" 2>/dev/null || true
  cp "$BATS_TEST_DIRNAME"/../lib/clm/*.sh "$CLM_ROOT/lib/clm/" 2>/dev/null || true
  chmod +x "$CLM_ROOT/bin/clm" 2>/dev/null || true
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `bats tests/common_test.bats`
Expected: FAIL — `lib/clm/common.sh` does not exist yet (source error).

- [ ] **Step 5: Implement `lib/clm/common.sh`**

```bash
#!/usr/bin/env bash

CLM_TARGET="${CLM_TARGET:-$HOME}"
CLM_VAULT="${CLM_VAULT:-${CLM_ROOT:-.}/vault}"

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

- [ ] **Step 6: Run the test to verify it passes**

Run: `bats tests/common_test.bats`
Expected: `5 tests, 0 failures`

- [ ] **Step 7: Commit**

```bash
git add .gitignore lib/clm/common.sh tests/test_helper.bash tests/common_test.bats
git commit -m "Add safety-layer primitives (clm::die, clm::confirm) with bats harness"
```

---

## Task 2: `stow` namespace library

**Files:**
- Create: `lib/clm/stow.sh`
- Create: `tests/stow_test.bats`

**Interfaces:**
- Consumes: `clm::die(message)` from Task 1.
- Consumes env vars `CLM_ROOT`, `CLM_TARGET` (set by caller/test harness).
- Produces: `clm::stow_packages()` — prints one stowable package name per line (top-level dirs of `$CLM_ROOT` excluding `vault`, `bin`, `lib`, `docs`, `.git`).
- Produces: `clm::is_stowed(pkg)` — returns 0 if every file in `$CLM_ROOT/<pkg>` has a corresponding symlink in `$CLM_TARGET` resolving back to it, 1 otherwise.
- Produces: `clm::validate_package(pkg)` — calls `clm::die` if `pkg` is excluded or doesn't exist under `$CLM_ROOT`.
- Produces: `cmd_stow_add(pkg)`, `cmd_stow_remove(pkg)`, `cmd_stow_onboard()`, `cmd_stow_list()` — consumed by `bin/clm` in Task 3.

- [ ] **Step 1: Write the failing tests**

Create `tests/stow_test.bats`:

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
  mkdir -p "$CLM_ROOT/zsh"
  echo 'export FOO=1' > "$CLM_ROOT/zsh/.zshrc"
}

@test "stow_packages lists zsh but excludes vault, bin, lib, docs" {
  mkdir -p "$CLM_ROOT/vault" "$CLM_ROOT/docs"
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    clm::stow_packages
  "
  [[ "$output" == *"zsh"* ]]
  [[ "$output" != *"vault"* ]]
  [[ "$output" != *"docs"* ]]
  [[ "$output" != *"bin"* ]]
}

@test "is_stowed is false before stowing and true after" {
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    clm::is_stowed zsh
  "
  [ "$status" -eq 1 ]

  mkdir -p "$CLM_TARGET"
  ln -s "$CLM_ROOT/zsh/.zshrc" "$CLM_TARGET/.zshrc"

  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    clm::is_stowed zsh
  "
  [ "$status" -eq 0 ]
}

@test "cmd_stow_add links the package into target" {
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_add zsh
  "
  [ "$status" -eq 0 ]
  [ -L "$CLM_TARGET/.zshrc" ]
}

@test "cmd_stow_add refuses an unknown package" {
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_add nonexistent
  "
  [ "$status" -ne 0 ]
}

@test "cmd_stow_add refuses to treat vault as a package" {
  mkdir -p "$CLM_ROOT/vault"
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_add vault
  "
  [ "$status" -ne 0 ]
}

@test "cmd_stow_add refuses when the target already has a conflicting non-symlink file" {
  mkdir -p "$CLM_TARGET"
  echo 'not managed by stow' > "$CLM_TARGET/.zshrc"
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_add zsh
  "
  [ "$status" -ne 0 ]
  [ ! -L "$CLM_TARGET/.zshrc" ]
}

@test "cmd_stow_remove asks for confirmation and removes the symlink when confirmed" {
  mkdir -p "$CLM_TARGET"
  ln -s "$CLM_ROOT/zsh/.zshrc" "$CLM_TARGET/.zshrc"
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    echo y | cmd_stow_remove zsh
  "
  [ "$status" -eq 0 ]
  [ ! -e "$CLM_TARGET/.zshrc" ]
}

@test "cmd_stow_remove aborts when not confirmed" {
  mkdir -p "$CLM_TARGET"
  ln -s "$CLM_ROOT/zsh/.zshrc" "$CLM_TARGET/.zshrc"
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    echo n | cmd_stow_remove zsh
  "
  [ "$status" -ne 0 ]
  [ -L "$CLM_TARGET/.zshrc" ]
}

@test "cmd_stow_onboard stows what's present and skips what isn't" {
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_onboard
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"stowed: zsh"* ]]
  [[ "$output" == *"skip (not present): bash"* ]]
}

@test "cmd_stow_list reports stowed state per package" {
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_add zsh >/dev/null
    cmd_stow_list
  "
  [[ "$output" == *"zsh [stowed]"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/stow_test.bats`
Expected: FAIL — `lib/clm/stow.sh` does not exist yet.

- [ ] **Step 3: Implement `lib/clm/stow.sh`**

```bash
#!/usr/bin/env bash

CLM_STOW_EXCLUDE=" vault bin lib docs .git "

clm::stow_packages() {
  local entry name
  for entry in "$CLM_ROOT"/*/; do
    [ -d "$entry" ] || continue
    name="$(basename "$entry")"
    case "$CLM_STOW_EXCLUDE" in
      *" $name "*) continue ;;
    esac
    echo "$name"
  done
}

clm::is_stowed() {
  local pkg="$1"
  local pkg_dir="$CLM_ROOT/$pkg"
  local file rel target_file link_target resolved
  [ -d "$pkg_dir" ] || return 1
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
  case "$CLM_STOW_EXCLUDE" in
    *" $pkg "*) clm::die "'$pkg' is not a stowable package" ;;
  esac
  [ -d "$CLM_ROOT/$pkg" ] || clm::die "no such package: $pkg"
}

cmd_stow_add() {
  local pkg="$1"
  clm::validate_package "$pkg"
  stow -d "$CLM_ROOT" -t "$CLM_TARGET" "$pkg"
  echo "stowed: $pkg"
}

cmd_stow_remove() {
  local pkg="$1"
  clm::validate_package "$pkg"
  clm::confirm "Unstow '$pkg' (remove its symlinks from $CLM_TARGET)?" || clm::die "aborted"
  stow -D -d "$CLM_ROOT" -t "$CLM_TARGET" "$pkg"
  echo "unstowed: $pkg"
}

cmd_stow_onboard() {
  local pkg
  for pkg in zsh bash git ssh; do
    if [ ! -d "$CLM_ROOT/$pkg" ]; then
      echo "skip (not present): $pkg"
      continue
    fi
    stow -d "$CLM_ROOT" -t "$CLM_TARGET" "$pkg"
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

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/stow_test.bats`
Expected: `9 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/clm/stow.sh tests/stow_test.bats
git commit -m "Add stow namespace: onboard/add/remove/list backed by native Stow conflict detection"
```

---

## Task 3: `bin/clm` dispatcher (stow noun only)

**Files:**
- Create: `bin/clm`
- Create: `tests/dispatch_test.bats`

**Interfaces:**
- Consumes: everything from `lib/clm/common.sh` and `lib/clm/stow.sh` (Tasks 1–2).
- Produces: the `clm` executable, resolving its own real location through symlinks to compute `CLM_ROOT` (needed because `clm-install.sh` in Task 7 symlinks this file into the Homebrew bin dir). Honors a `--yes` flag anywhere in the argument list, setting `CLM_YES=1`.

- [ ] **Step 1: Write the failing tests**

Create `tests/dispatch_test.bats`:

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
  mkdir -p "$CLM_ROOT/zsh"
  echo 'x' > "$CLM_ROOT/zsh/.zshrc"
}

@test "clm with no args prints usage and exits 1" {
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/bin/clm"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: clm"* ]]
}

@test "clm with an unknown noun prints usage and exits 1" {
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/bin/clm" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: clm"* ]]
}

@test "clm stow with an unknown verb prints usage and exits 1" {
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/bin/clm" stow bogus
  [ "$status" -eq 1 ]
}

@test "clm stow add works end to end through the dispatcher" {
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/bin/clm" stow add zsh
  [ "$status" -eq 0 ]
  [ -L "$CLM_TARGET/.zshrc" ]
}

@test "--yes is parsed and not treated as a package name" {
  env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/bin/clm" stow add zsh
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/bin/clm" stow remove zsh --yes
  [ "$status" -eq 0 ]
  [ ! -e "$CLM_TARGET/.zshrc" ]
}

@test "clm resolves its root correctly even when invoked through a symlink" {
  ln -s "$CLM_ROOT/bin/clm" "$BATS_TEST_TMPDIR/clm-link"
  run env CLM_TARGET="$CLM_TARGET" "$BATS_TEST_TMPDIR/clm-link" stow add zsh
  [ "$status" -eq 0 ]
  [ -L "$CLM_TARGET/.zshrc" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/dispatch_test.bats`
Expected: FAIL — `bin/clm` does not exist yet.

- [ ] **Step 3: Implement `bin/clm`**

```bash
#!/usr/bin/env bash
set -e

resolve_root() {
  local source="${BASH_SOURCE[0]}"
  local dir
  while [ -L "$source" ]; do
    dir="$(cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd)"
    source="$(readlink "$source")"
    case "$source" in
      /*) ;;
      *) source="$dir/$source" ;;
    esac
  done
  cd -P "$(dirname "$source")/.." >/dev/null 2>&1 && pwd
}

CLM_ROOT="${CLM_ROOT:-$(resolve_root)}"
export CLM_ROOT
CLM_TARGET="${CLM_TARGET:-$HOME}"
export CLM_TARGET
CLM_VAULT="${CLM_VAULT:-$CLM_ROOT/vault}"
export CLM_VAULT

# shellcheck source=lib/clm/common.sh
source "$CLM_ROOT/lib/clm/common.sh"
# shellcheck source=lib/clm/stow.sh
source "$CLM_ROOT/lib/clm/stow.sh"

usage() {
  cat <<'EOF'
Usage: clm <noun> <verb> [args] [--yes]

Nouns:
  stow    onboard | add <pkg> | remove <pkg> | list
EOF
}

main() {
  CLM_YES=0
  filtered=()
  for a in "$@"; do
    if [ "$a" = "--yes" ]; then
      CLM_YES=1
    else
      filtered+=("$a")
    fi
  done
  export CLM_YES
  set -- "${filtered[@]}"

  if [ "$#" -eq 0 ] || [ -z "$1" ]; then
    usage
    exit 1
  fi

  noun="$1"
  shift

  case "$noun" in
    stow)
      verb="${1:-}"
      [ "$#" -gt 0 ] && shift
      case "$verb" in
        onboard) cmd_stow_onboard ;;
        add) [ -n "${1:-}" ] || clm::die "package name required"; cmd_stow_add "$1" ;;
        remove) [ -n "${1:-}" ] || clm::die "package name required"; cmd_stow_remove "$1" ;;
        list) cmd_stow_list ;;
        *) usage; exit 1 ;;
      esac
      ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
```

- [ ] **Step 4: Make it executable and run the tests**

Run: `chmod +x bin/clm && bats tests/dispatch_test.bats`
Expected: `6 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add bin/clm tests/dispatch_test.bats
git commit -m "Add clm CLI dispatcher with symlink-safe root resolution and --yes parsing"
```

---

## Task 4: Migrate existing dotfiles content and add the `ssh` package

**Files:**
- Create: `zsh/.zshrc` (copied from `~/dotfiles/zsh/.zshrc`)
- Create: `bash/.bash_profile`, `bash/.profile` (copied from `~/dotfiles/bash/`)
- Create: `git/.gitconfig`, `git/.config/git/ignore` (copied from `~/dotfiles/git/`)
- Create: `ssh/.ssh/config` (new content, not migrated)
- Create: `tests/ssh_package_test.bats`

**Interfaces:**
- Consumes: `cmd_stow_add` from Task 2/3 (used by the test to verify the new `ssh` package stows cleanly).
- No new functions produced — this task is data migration plus one new Stow package.

- [ ] **Step 1: Write the failing test for the new `ssh` package**

Create `tests/ssh_package_test.bats`:

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
  mkdir -p "$CLM_ROOT/ssh/.ssh"
  cp "$BATS_TEST_DIRNAME/../ssh/.ssh/config" "$CLM_ROOT/ssh/.ssh/config"
}

@test "ssh package stows cleanly" {
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/bin/clm" stow add ssh
  [ "$status" -eq 0 ]
  [ -L "$CLM_TARGET/.ssh/config" ]
}

@test "ssh config with unmet vault includes still parses without error" {
  env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/bin/clm" stow add ssh
  run ssh -F "$CLM_TARGET/.ssh/config" -G somehost
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/ssh_package_test.bats`
Expected: FAIL — `ssh/.ssh/config` (the file `setup()` tries to `cp`) does not exist yet.

- [ ] **Step 3: Copy existing packages from `~/dotfiles` (read-only on the source — `~/dotfiles` and its live symlinks are not touched) and create the new `ssh` package**

```bash
mkdir -p zsh bash git/.config/git ssh/.ssh
cp ~/dotfiles/zsh/.zshrc zsh/.zshrc
cp ~/dotfiles/bash/.bash_profile bash/.bash_profile
cp ~/dotfiles/bash/.profile bash/.profile
cp ~/dotfiles/git/.gitconfig git/.gitconfig
cp ~/dotfiles/git/.config/git/ignore git/.config/git/ignore
```

Create `ssh/.ssh/config`:

```
Include ~/clm/vault/global/ssh/config
Include ~/clm/vault/projects/*/ssh/config

Host *
    IdentitiesOnly yes
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/ssh_package_test.bats`
Expected: `2 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add zsh bash git ssh tests/ssh_package_test.bats
git commit -m "Migrate zsh/bash/git packages from ~/dotfiles and add the ssh package"
```

---

## Task 5: Vault skeleton and `fix-perms.sh`

**Files:**
- Create: `vault/README.md`
- Create: `vault/global/ssh/config`
- Create: `vault/global/ssh/keys/.gitkeep`
- Create: `vault/projects/.gitkeep`
- Create: `vault/bin/fix-perms.sh`
- Create: `tests/vault_fixperms_script_test.bats`

**Interfaces:**
- Produces: `vault/bin/fix-perms.sh <vault-root>` — standalone script (no dependency on `lib/clm`), chmods `700` on `global/ssh/keys` and each `projects/*/ssh/keys` directory, `600` on the regular files inside them. Silently no-ops on a directory that doesn't exist (a project with no keys yet is valid).

- [ ] **Step 1: Write the failing tests**

Create `tests/vault_fixperms_script_test.bats`:

```bash
#!/usr/bin/env bats

@test "fix-perms sets 700 on key dirs and 600 on key files, global and per-project" {
  root="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$root/global/ssh/keys" "$root/projects/acme/ssh/keys" "$root/bin"
  cp "$BATS_TEST_DIRNAME/../vault/bin/fix-perms.sh" "$root/bin/fix-perms.sh"
  chmod +x "$root/bin/fix-perms.sh"
  echo "fake" > "$root/global/ssh/keys/id_ed25519"
  chmod 644 "$root/global/ssh/keys/id_ed25519"
  echo "fake" > "$root/projects/acme/ssh/keys/id_ed25519"
  chmod 644 "$root/projects/acme/ssh/keys/id_ed25519"

  run "$root/bin/fix-perms.sh" "$root"
  [ "$status" -eq 0 ]

  [ "$(stat -f '%Lp' "$root/global/ssh/keys")" = "700" ]
  [ "$(stat -f '%Lp' "$root/global/ssh/keys/id_ed25519")" = "600" ]
  [ "$(stat -f '%Lp' "$root/projects/acme/ssh/keys/id_ed25519")" = "600" ]
}

@test "fix-perms does not error when a project has no keys directory yet" {
  root="$BATS_TEST_TMPDIR/vault"
  mkdir -p "$root/global/ssh/keys" "$root/projects/emptyproj/ssh" "$root/bin"
  cp "$BATS_TEST_DIRNAME/../vault/bin/fix-perms.sh" "$root/bin/fix-perms.sh"
  chmod +x "$root/bin/fix-perms.sh"

  run "$root/bin/fix-perms.sh" "$root"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/vault_fixperms_script_test.bats`
Expected: FAIL — `vault/bin/fix-perms.sh` does not exist yet.

- [ ] **Step 3: Implement `vault/bin/fix-perms.sh`**

```bash
#!/usr/bin/env bash
set -e

VAULT_ROOT="${1:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

fix_keys_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  chmod 700 "$dir"
  local f
  for f in "$dir"/*; do
    [ -e "$f" ] || continue
    [ -f "$f" ] && chmod 600 "$f"
  done
}

fix_keys_dir "$VAULT_ROOT/global/ssh/keys"

for proj in "$VAULT_ROOT"/projects/*/; do
  [ -d "$proj" ] || continue
  fix_keys_dir "${proj}ssh/keys"
done

echo "vault key permissions fixed"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `chmod +x vault/bin/fix-perms.sh && bats tests/vault_fixperms_script_test.bats`
Expected: `2 tests, 0 failures`

- [ ] **Step 5: Add the rest of the vault skeleton (README, templates, placeholders)**

Create `vault/global/ssh/config`:

```
# Host blocks for keys that should always be available, regardless of project.
# Example:
#
# Host github.com-personal
#     HostName github.com
#     User git
#     IdentityFile ~/clm/vault/global/ssh/keys/id_ed25519_personal
```

Create `vault/global/ssh/keys/.gitkeep` (empty file).

Create `vault/projects/.gitkeep` (empty file).

Create `vault/README.md`:

```markdown
# vault

Private, machine-secrets counterpart to `~/clm`. Never pushed to a public remote.

## Layout

- `global/ssh/` — SSH keys and Host blocks that are always active, regardless of
  which project you're working on (personal GitHub, personal servers).
- `projects/<name>/ssh/` — SSH keys and Host blocks scoped to one project or
  client engagement.
- `bin/fix-perms.sh` — sets correct permissions (700 on key directories, 600 on
  key files) after a fresh clone. Run via `clm vault fix-perms`.

## Adding a new project

    mkdir -p projects/<name>/ssh/keys
    # add your key(s) to projects/<name>/ssh/keys/
    # add a Host block to projects/<name>/ssh/config referencing them
    clm vault fix-perms

`~/clm`'s stowed `ssh/.ssh/config` already includes `projects/*/ssh/config` via a
glob, so a new project's hosts are picked up automatically — no further
registration needed.

## Adding a new machine

    git clone <this-repo-url> ~/clm/vault
    clm vault fix-perms
```

- [ ] **Step 6: Initialize vault as its own git repo**

```bash
cd vault
git init -q
git add -A
git commit -q -m "Initial vault skeleton"
cd ..
```

- [ ] **Step 7: Commit the outer repo (vault/ itself is gitignored per Task 1, so this only commits the fix-perms test)**

```bash
git add tests/vault_fixperms_script_test.bats
git commit -m "Add vault skeleton and fix-perms.sh with scoped, non-recursive-blind chmod"
```

---

## Task 6: `vault` and `status` CLI namespaces

**Files:**
- Create: `lib/clm/vault.sh`
- Create: `lib/clm/status.sh`
- Modify: `bin/clm` (source the two new libs, add `vault` and `status` nouns, update usage text)
- Create: `tests/vault_cmd_test.bats`
- Create: `tests/status_test.bats`

**Interfaces:**
- Consumes: `clm::die` (Task 1), `clm::stow_packages`/`clm::is_stowed` (Task 2), `CLM_VAULT` env var.
- Produces: `cmd_vault_fix_perms()` — dies if `$CLM_VAULT` doesn't exist or its `bin/fix-perms.sh` is missing/non-executable; otherwise execs it.
- Produces: `cmd_status()` — prints stow package states plus vault presence/permission health.

- [ ] **Step 1: Write the failing tests**

Create `tests/vault_cmd_test.bats`:

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
}

@test "clm vault fix-perms refuses when vault has not been cloned" {
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_VAULT="$CLM_VAULT" "$CLM_ROOT/bin/clm" vault fix-perms
  [ "$status" -ne 0 ]
  [[ "$output" == *"vault not found"* ]]
}

@test "clm vault fix-perms runs the vault's own fix-perms.sh" {
  mkdir -p "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  cp "$BATS_TEST_DIRNAME/../vault/bin/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  echo fake > "$CLM_VAULT/global/ssh/keys/id_ed25519"
  chmod 644 "$CLM_VAULT/global/ssh/keys/id_ed25519"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_VAULT="$CLM_VAULT" "$CLM_ROOT/bin/clm" vault fix-perms
  [ "$status" -eq 0 ]
  [ "$(stat -f '%Lp' "$CLM_VAULT/global/ssh/keys/id_ed25519")" = "600" ]
}
```

Create `tests/status_test.bats`:

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
  mkdir -p "$CLM_ROOT/zsh"
  echo 'x' > "$CLM_ROOT/zsh/.zshrc"
}

@test "clm status runs cleanly with no vault present" {
  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_VAULT="$CLM_VAULT" "$CLM_ROOT/bin/clm" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Vault: not found"* ]]
  [[ "$output" == *"zsh [not stowed]"* ]]
}

@test "clm status reports a stowed package and vault key permission warnings" {
  env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" "$CLM_ROOT/bin/clm" stow add zsh
  mkdir -p "$CLM_VAULT/global/ssh/keys"
  chmod 755 "$CLM_VAULT/global/ssh/keys"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_VAULT="$CLM_VAULT" "$CLM_ROOT/bin/clm" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"zsh [stowed]"* ]]
  [[ "$output" == *"WARNING"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/vault_cmd_test.bats tests/status_test.bats`
Expected: FAIL — `clm` doesn't recognize `vault`/`status` nouns yet.

- [ ] **Step 3: Implement `lib/clm/vault.sh`**

```bash
#!/usr/bin/env bash

cmd_vault_fix_perms() {
  [ -d "$CLM_VAULT" ] || clm::die "vault not found at $CLM_VAULT (clone it first: git clone <vault-repo-url> $CLM_VAULT)"
  local script="$CLM_VAULT/bin/fix-perms.sh"
  [ -x "$script" ] || clm::die "missing or non-executable: $script"
  "$script" "$CLM_VAULT"
}
```

- [ ] **Step 4: Implement `lib/clm/status.sh`**

```bash
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
```

- [ ] **Step 5: Modify `bin/clm` to wire in the new namespaces**

Update the source block to add:

```bash
# shellcheck source=lib/clm/vault.sh
source "$CLM_ROOT/lib/clm/vault.sh"
# shellcheck source=lib/clm/status.sh
source "$CLM_ROOT/lib/clm/status.sh"
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
EOF
}
```

Update the `case "$noun" in ... esac` block in `main()` to add, alongside the existing `stow)` arm:

```bash
    vault)
      verb="${1:-}"
      [ "$#" -gt 0 ] && shift
      case "$verb" in
        fix-perms) cmd_vault_fix_perms ;;
        *) usage; exit 1 ;;
      esac
      ;;
    status) cmd_status ;;
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bats tests/vault_cmd_test.bats tests/status_test.bats tests/dispatch_test.bats tests/stow_test.bats`
Expected: all files pass (`2 tests`, `2 tests`, `6 tests`, `9 tests` — `0 failures` each). Re-running the earlier suites confirms this change didn't regress the `stow` noun.

- [ ] **Step 7: Commit**

```bash
git add lib/clm/vault.sh lib/clm/status.sh bin/clm tests/vault_cmd_test.bats tests/status_test.bats
git commit -m "Add clm vault fix-perms and clm status"
```

---

## Task 7: `clm-install.sh` bootstrap

**Files:**
- Create: `clm-install.sh`
- Create: `tests/clm_install_test.bats`

**Interfaces:**
- Consumes: `clm::die`, `clm::confirm` from `lib/clm/common.sh`.
- Produces: the one-shot bootstrap entry point — checks/installs Homebrew, checks/installs Stow, symlinks `bin/clm` into `$(brew --prefix)/bin/clm`.

- [ ] **Step 1: Write the failing tests**

Create `tests/clm_install_test.bats`:

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
  cp "$BATS_TEST_DIRNAME/../clm-install.sh" "$CLM_ROOT/clm-install.sh"
  chmod +x "$CLM_ROOT/clm-install.sh"
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  BREW_PREFIX="$BATS_TEST_TMPDIR/brewprefix"
  mkdir -p "$FAKE_BIN" "$BREW_PREFIX/bin"
}

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
exit 1
EOF
  chmod +x "$FAKE_BIN/brew"
}

write_fake_stow() {
  cat > "$FAKE_BIN/stow" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$FAKE_BIN/stow"
}

@test "install links clm into the brew prefix when brew and stow are present" {
  write_fake_brew
  write_fake_stow
  run env PATH="$FAKE_BIN:$PATH" "$CLM_ROOT/clm-install.sh"
  [ "$status" -eq 0 ]
  [ -L "$BREW_PREFIX/bin/clm" ]
}

@test "install runs brew install stow when stow is missing" {
  write_fake_brew
  run env PATH="$FAKE_BIN:$PATH" "$CLM_ROOT/clm-install.sh"
  [ "$status" -eq 0 ]
  grep -q "installed: stow" "$BREW_PREFIX/installed.log"
}

@test "install refuses when brew is missing and not confirmed" {
  run env PATH="/usr/bin:/bin" "$CLM_ROOT/clm-install.sh" <<< "n"
  [ "$status" -ne 0 ]
}

@test "install invokes the configured install command when brew is missing and confirmed" {
  marker="$BATS_TEST_TMPDIR/marker"
  run env PATH="/usr/bin:/bin" CLM_INSTALL_BREW_INSTALL_CMD="touch '$marker'" "$CLM_ROOT/clm-install.sh" <<< "y"
  [ -e "$marker" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/clm_install_test.bats`
Expected: FAIL — `clm-install.sh` does not exist yet.

- [ ] **Step 3: Implement `clm-install.sh`**

```bash
#!/usr/bin/env bash
set -e

CLM_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CLM_ROOT
CLM_TARGET="${CLM_TARGET:-$HOME}"
export CLM_TARGET
CLM_VAULT="${CLM_VAULT:-$CLM_ROOT/vault}"
export CLM_VAULT
CLM_YES="${CLM_YES:-0}"
export CLM_YES

# shellcheck source=lib/clm/common.sh
source "$CLM_ROOT/lib/clm/common.sh"

BREW_INSTALL_CMD="${CLM_INSTALL_BREW_INSTALL_CMD:-/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"}"

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    echo "Homebrew: found"
    return
  fi
  clm::confirm "Homebrew not found. Install it now?" || clm::die "Homebrew is required; aborting"
  eval "$BREW_INSTALL_CMD"
}

ensure_stow() {
  if command -v stow >/dev/null 2>&1; then
    echo "stow: found"
    return
  fi
  echo "stow not found, installing via Homebrew..."
  brew install stow
}

link_clm_cli() {
  chmod +x "$CLM_ROOT/bin/clm"
  local prefix
  prefix="$(brew --prefix)"
  mkdir -p "$prefix/bin"
  ln -sf "$CLM_ROOT/bin/clm" "$prefix/bin/clm"
  echo "linked: $prefix/bin/clm -> $CLM_ROOT/bin/clm"
}

main() {
  ensure_homebrew
  ensure_stow
  link_clm_cli
  cat <<EOF

Done. 'clm' is now on your PATH.

Next steps:
  clm stow onboard
  git clone <vault-repo-url> $CLM_VAULT
  clm vault fix-perms
EOF
}

main "$@"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `chmod +x clm-install.sh && bats tests/clm_install_test.bats`
Expected: `4 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add clm-install.sh tests/clm_install_test.bats
git commit -m "Add clm-install.sh bootstrap: Homebrew/Stow check, global clm symlink"
```

---

## Task 8: Umbrella README and full-suite verification

**Files:**
- Create: `README.md`

**Interfaces:** None — documentation only, describing the CLI surface built in Tasks 1–7.

- [ ] **Step 1: Write `README.md`**

```markdown
# clm — Chris Luu Machine

Everything about how this machine is set up lives here: Stow-managed dotfiles,
a private secrets vault, and the `clm` CLI that ties them together.

## First-time setup on a new machine

    git clone <this-repo-url> ~/clm
    cd ~/clm && ./clm-install.sh
    clm stow onboard
    git clone <vault-repo-url> ~/clm/vault
    clm vault fix-perms

## Layout

- `zsh/`, `bash/`, `git/`, `ssh/` — GNU Stow packages. Never run `stow` (or
  `clm stow add/remove`) against `vault` or `bin` — they aren't packages.
- `vault/` — a separate, private, gitignored nested git repo. See
  `vault/README.md`. Clone it independently; it's never part of this repo's
  history.
- `bin/clm` — the CLI. `lib/clm/*.sh` holds one module per noun.
- `clm-install.sh` — one-time bootstrap (Homebrew, Stow, puts `clm` on PATH).

## `clm` commands

    clm stow onboard          # stow zsh, bash, git, ssh in one shot
    clm stow add <package>    # stow one package
    clm stow remove <package> # unstow one package (asks for confirmation)
    clm stow list             # show stow state of every package
    clm vault fix-perms       # fix key file/dir permissions in ~/clm/vault
    clm status                # stow + vault health check

Every subcommand accepts `--yes` to skip confirmation prompts.

## Safety

- Stow conflicts (an existing non-symlink file at a target path) are refused
  natively by GNU Stow — nothing here overrides that.
- `clm stow remove` and the Homebrew install step in `clm-install.sh` prompt
  for confirmation unless `--yes`/`CLM_YES=1` is set.
- All permission fixes (`clm vault fix-perms`) touch only the specific,
  named key directories — never a blanket recursive chmod over `~/clm` or
  `~/clm/vault`.

## What's not here yet

- Installing macOS apps/CLI tools (a future `clm install` namespace).
- Vaulting tool-managed auth (`gh`, `vercel`, `npm login`, Docker registry).
- Per-project "active project" switching for single-file configs (`.npmrc`,
  `.env`, docker-compose) — the planned project hub, a future `clm project`
  namespace.

See `docs/superpowers/specs/2026-07-15-clm-foundation-design.md` for the full
design rationale.
```

- [ ] **Step 2: Run the full test suite**

Run: `bats tests/`
Expected: all test files pass, `0 failures` across the board.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Add umbrella README documenting the clm CLI and layout"
```

---

## Manual follow-up (not automated by this plan)

Once all 8 tasks are committed, going live on this machine is a deliberate,
manual step outside this plan:

1. `mv ~/machine-setup ~/clm` (or clone this repo fresh to `~/clm`).
2. `cd ~/clm && ./clm-install.sh`
3. `clm stow onboard` — this is the point where real symlinks land in the
   real `$HOME`, superseding whatever `~/dotfiles` currently has stowed.
   Unstow `~/dotfiles`'s packages first (`cd ~/dotfiles && stow -D zsh bash
   git`) to avoid Stow conflicts.
4. Create or clone the real `vault` repo to `~/clm/vault`, add real SSH keys,
   `clm vault fix-perms`.
