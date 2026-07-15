# clm pack Archive Addendum Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `pack/` output gitignored, and give `clm pack all` a final step that archives the whole `$CLM_ROOT` tree (dotfiles + vault + pack output) into an unencrypted, timestamped `.tar.gz`, per the addendum in `docs/superpowers/specs/2026-07-15-clm-pack-design.md`.

**Architecture:** One new function, `clm::pack_archive`, added to the existing `lib/clm/pack.sh`; `cmd_pack_all` calls it as its final step.

**Tech Stack:** Bash (bash 3.2 compatible), `tar`, bats-core for testing.

## Global Constraints

- Same as the CLM foundation/pack plans: bash 3.2 compatible, tests run against temp directories only (`CLM_ROOT`/`CLM_PACK_DIR`/`CLM_BACKUP_DIR` overrides), never the real `$HOME`.
- The archive is **not encrypted** — a deliberate user choice. Do not add encryption.
- Default archive destination (`$HOME/clm-backups`) must stay outside any git-tracked directory.

---

## Task 1: Gitignore pack/, add clm::pack_archive, wire into cmd_pack_all

**Files:**
- Modify: `.gitignore` (add `pack/`)
- Modify: `lib/clm/pack.sh` (add `CLM_BACKUP_DIR`, `clm::pack_archive`, call it from `cmd_pack_all`)
- Modify: `tests/pack_test.bats` (add archive coverage)
- Modify: `README.md` (reflect gitignored pack/, document the archive)

**Interfaces:**
- Consumes: `CLM_ROOT` (the tree to archive).
- Produces: `CLM_BACKUP_DIR` env var (default `$HOME/clm-backups`, overridable). `clm::pack_archive()` — creates `$CLM_BACKUP_DIR/clm-backup-<timestamp>.tar.gz` from the entire `$CLM_ROOT` tree, prints `archived: -> <path>`.

- [ ] **Step 1: Write the failing test**

Add to `tests/pack_test.bats` (append at the end of the file, before nothing — bats files don't need a footer):

```bash

@test "cmd_pack_all also produces a full-machine archive" {
  mkdir -p "$CLM_ROOT/zsh" "$CLM_ROOT/vault/global/ssh/keys"
  echo 'export FOO=1' > "$CLM_ROOT/zsh/.zshrc"
  echo 'fake-key-material' > "$CLM_ROOT/vault/global/ssh/keys/id_ed25519"
  backup_dir="$BATS_TEST_TMPDIR/clm-backups"

  run bash -c "
    export CLM_ROOT='$CLM_ROOT' CLM_PACK_DIR='$CLM_ROOT/pack' CLM_BACKUP_DIR='$backup_dir'
    export PATH='/usr/bin:/bin'
    source '$CLM_ROOT/lib/clm/common.sh'
    source '$CLM_ROOT/lib/clm/pack.sh'
    cmd_pack_all
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"archived: ->"* ]]

  archive="$(find "$backup_dir" -name 'clm-backup-*.tar.gz')"
  [ -n "$archive" ]
  tar tzf "$archive" | grep -q "zsh/.zshrc"
  tar tzf "$archive" | grep -q "vault/global/ssh/keys/id_ed25519"
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/pack_test.bats`
Expected: FAIL — `cmd_pack_all` doesn't produce an archive yet (no `archived: ->` in output).

- [ ] **Step 3: Add `pack/` to `.gitignore`**

```
vault/
pack/
.DS_Store
```

- [ ] **Step 4: Implement `clm::pack_archive` and wire it into `cmd_pack_all` in `lib/clm/pack.sh`**

Add near the top, after `CLM_PACK_DIR`:

```bash
CLM_BACKUP_DIR="${CLM_BACKUP_DIR:-$HOME/clm-backups}"
```

Add a new function (place it after `clm::pack_run`, before `cmd_pack_list`):

```bash
clm::pack_archive() {
  mkdir -p "$CLM_BACKUP_DIR"
  local timestamp archive
  timestamp="$(date +%Y%m%d-%H%M%S)"
  archive="$CLM_BACKUP_DIR/clm-backup-$timestamp.tar.gz"
  tar czf "$archive" -C "$(dirname "$CLM_ROOT")" "$(basename "$CLM_ROOT")" || clm::die "archive creation failed"
  echo "archived: -> $archive"
}
```

Modify `cmd_pack_all` to call it as the final step:

```bash
cmd_pack_all() {
  local c
  while IFS= read -r c; do
    cmd_pack_one "$c"
  done < <(clm::pack_checkers)
  clm::pack_archive
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bats tests/pack_test.bats`
Expected: `7 tests, 0 failures`

- [ ] **Step 6: Run the full suite to confirm no regressions**

Run: `bats tests/`
Expected: all test files pass (44 tests total, 0 failures) — note `tests/pack_dispatch_test.bats`'s `"clm pack all works end to end"` test now also triggers an archive step; confirm it still passes (it doesn't assert on archive output, so it should, but verify).

- [ ] **Step 7: Update `README.md`**

In `## Layout`, change the `pack/` line to:

```markdown
- `pack/` — captured machine-state manifests (Brewfile, extension lists, etc.),
  produced by `clm pack`. Gitignored — regenerable, not worth tracking.
```

In `## \`clm\` commands`, update the `clm pack all` line and add a note:

```markdown
    clm pack all                # capture everything available, then archive the whole ~/clm tree
```

Add a new subsection after `## Safety`:

```markdown
## Backups

`clm pack all` finishes by archiving the entire `~/clm` tree (dotfiles,
vault, and the pack output it just generated) into a single timestamped
`.tar.gz` under `~/clm-backups/` (override with `CLM_BACKUP_DIR`). This
archive is **not encrypted** — it contains real SSH private keys in
plaintext, so treat the resulting file with the same care as the keys
themselves (e.g. only copy it to storage that's already encrypted).
```

- [ ] **Step 8: Commit**

```bash
git add .gitignore lib/clm/pack.sh tests/pack_test.bats README.md
git commit -m "Gitignore pack/ output; clm pack all now archives the whole clm tree"
```
