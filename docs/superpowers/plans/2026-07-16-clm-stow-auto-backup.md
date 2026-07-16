# Auto-Backup on Stow Conflict Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `clm stow add`/`clm stow onboard` automatically back up a conflicting pre-existing target file (never clobbering an earlier backup) and retry, instead of just failing with Stow's raw error, per the addendum in `docs/superpowers/specs/2026-07-15-clm-foundation-design.md`.

**Architecture:** New `clm::stow_backup_conflicts(pkg)` in `lib/clm/stow.sh`, run via a dry-run (`stow -n`) before the real `stow` call in both `cmd_stow_add` and `cmd_stow_onboard`.

**Tech Stack:** Bash (bash 3.2 compatible), GNU Stow, `sed`, bats-core.

## Global Constraints

- Never delete anything — a conflicting file is always renamed (`.clm-backup`), never removed.
- Never clobber an existing backup — if `.clm-backup` is already taken, use `.clm-backup.<n>` with an incrementing `n`.
- Only ever touches a target that is (a) a real conflict Stow itself reported and (b) confirmed to still be a non-symlink file at backup time (defense against acting on stale/misparsed data).

---

## Task 1: `clm::stow_backup_conflicts`

**Files:**
- Modify: `lib/clm/stow.sh`
- Modify: `tests/stow_test.bats`

**Interfaces:**
- Produces: `clm::stow_backup_conflicts(pkg)` — called from `cmd_stow_add` and `cmd_stow_onboard`, before the real `stow` invocation.

- [ ] **Step 1: Update the test whose expectation changes (refuse → auto-backup-and-succeed)**

Replace:

```bash
@test "cmd_stow_add refuses when the target already has a conflicting non-symlink file" {
  mkdir -p "$CLM_TARGET"
  echo 'not managed by stow' > "$CLM_TARGET/.zshrc"
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET' CLM_DOTFILES_DIR='$CLM_DOTFILES_DIR'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_add zsh
  "
  [ "$status" -ne 0 ]
  [ ! -L "$CLM_TARGET/.zshrc" ]
}
```

with:

```bash
@test "cmd_stow_add backs up a conflicting non-symlink file and succeeds" {
  mkdir -p "$CLM_TARGET"
  echo 'not managed by stow' > "$CLM_TARGET/.zshrc"
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET' CLM_DOTFILES_DIR='$CLM_DOTFILES_DIR'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_add zsh
  "
  [ "$status" -eq 0 ]
  [ -L "$CLM_TARGET/.zshrc" ]
  [ -f "$CLM_TARGET/.zshrc.clm-backup" ]
  [ "$(cat "$CLM_TARGET/.zshrc.clm-backup")" = "not managed by stow" ]
}

@test "cmd_stow_add does not clobber an existing .clm-backup, uses a numbered suffix instead" {
  mkdir -p "$CLM_TARGET"
  echo 'first conflict' > "$CLM_TARGET/.zshrc"
  echo 'earlier backup, keep me' > "$CLM_TARGET/.zshrc.clm-backup"
  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_TARGET='$CLM_TARGET' CLM_DOTFILES_DIR='$CLM_DOTFILES_DIR'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/stow.sh'
    cmd_stow_add zsh
  "
  [ "$status" -eq 0 ]
  [ -L "$CLM_TARGET/.zshrc" ]
  [ "$(cat "$CLM_TARGET/.zshrc.clm-backup")" = "earlier backup, keep me" ]
  [ -f "$CLM_TARGET/.zshrc.clm-backup.1" ]
  [ "$(cat "$CLM_TARGET/.zshrc.clm-backup.1")" = "first conflict" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/stow_test.bats`
Expected: FAIL on both new/updated tests — `clm::stow_backup_conflicts` doesn't exist yet, and `cmd_stow_add` still just refuses.

- [ ] **Step 3: Implement `clm::stow_backup_conflicts` in `lib/clm/stow.sh`**

Add it above `cmd_stow_add`:

```bash
clm::stow_backup_conflicts() {
  local pkg="$1"
  local rel target backup n
  stow --no-folding -n -d "$CLM_DOTFILES_DIR" -t "$CLM_TARGET" "$pkg" 2>&1 | grep "cannot stow" | while IFS= read -r line; do
    rel="$(echo "$line" | sed -E 's/.*over existing target (.*) since.*/\1/')"
    [ -n "$rel" ] || continue
    target="$CLM_TARGET/$rel"
    [ -e "$target" ] || continue
    [ -L "$target" ] && continue
    backup="$target.clm-backup"
    n=1
    while [ -e "$backup" ]; do
      backup="$target.clm-backup.$n"
      n=$((n + 1))
    done
    mv "$target" "$backup"
    echo "backed up conflicting file: $target -> $backup"
  done
}
```

Update `cmd_stow_add` and `cmd_stow_onboard` to call it first:

```bash
cmd_stow_add() {
  local pkg="$1"
  clm::validate_package "$pkg"
  clm::stow_backup_conflicts "$pkg"
  stow --no-folding -d "$CLM_DOTFILES_DIR" -t "$CLM_TARGET" "$pkg" || clm::die "stow failed for '$pkg' (see conflicts above)"
  echo "stowed: $pkg"
}
```

```bash
cmd_stow_onboard() {
  local pkg
  for pkg in zsh bash git ssh; do
    if [ ! -d "$CLM_DOTFILES_DIR/$pkg" ]; then
      echo "skip (not present): $pkg"
      continue
    fi
    clm::stow_backup_conflicts "$pkg"
    stow --no-folding -d "$CLM_DOTFILES_DIR" -t "$CLM_TARGET" "$pkg" || clm::die "stow failed for '$pkg' (see conflicts above)"
    echo "stowed: $pkg"
  done
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/stow_test.bats`
Expected: all pass.

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `bats tests/`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/clm/stow.sh tests/stow_test.bats
git commit -m "clm stow: auto-backup a conflicting pre-existing file instead of just refusing"
```

---

## Task 2: README update

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the Safety section**

Change:

```markdown
- Stow conflicts (an existing non-symlink file at a target path) are refused
  natively by GNU Stow — nothing here overrides that. `--no-folding` is always
  passed so a not-yet-existing target directory (like `~/.ssh`) gets its
  individual files symlinked rather than becoming one directory-level symlink.
```

to:

```markdown
- Stow conflicts (an existing non-symlink file at a target path) are
  detected via a dry-run before every real `stow` call. The conflicting
  file is renamed to `<name>.clm-backup` (never clobbering an earlier
  backup — `.clm-backup.1`, `.clm-backup.2`, ... if needed) and the real
  stow retries — nothing is ever deleted, and nothing is silently
  overwritten either. `--no-folding` is always passed so a not-yet-existing
  target directory (like `~/.ssh`) gets its individual files symlinked
  rather than becoming one directory-level symlink.
```

- [ ] **Step 2: Run the full test suite one more time**

Run: `bats tests/`
Expected: all tests pass, `0 failures`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document auto-backup-on-conflict behavior in clm stow"
```
