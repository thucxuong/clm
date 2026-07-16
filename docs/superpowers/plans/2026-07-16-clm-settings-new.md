# clm settings new Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `clm settings new [machine-name] [--from <source-machine>]` scaffolds a new machine's folder in `cl-settings`, per the addendum in `docs/superpowers/specs/2026-07-15-clm-settings-consolidation-design.md`.

**Architecture:** `lib/clm/templates/fix-perms.sh` becomes the canonical vault-skeleton template (moved from `tests/fixtures/`, which was test-only). New `lib/clm/settings.sh` with `cmd_settings_new`, wired into `bin/clm` as a new `settings` noun.

**Tech Stack:** Bash (bash 3.2 compatible), `sed` (BSD, macOS), bats-core.

## Global Constraints

- Same bash 3.2 constraints as prior plans.
- `vault/` and `pack/` are *always* freshly scaffolded empty — never copied from another machine, regardless of `--from`. Only `dotfiles/` is ever copied.
- Refuse (don't guess) when: `cl-settings` isn't cloned, the target already exists, or `--from`'s source machine doesn't exist.

---

## Task 1: Move `fix-perms.sh` to a canonical runtime template location

**Files:**
- Create: `lib/clm/templates/fix-perms.sh`
- Delete: `tests/fixtures/fix-perms.sh`
- Modify: `tests/clm_install_test.bats`, `tests/vault_cmd_test.bats`, `tests/unpack_test.bats`, `tests/vault_fixperms_script_test.bats` (all four just change the source path they `cp` from)

- [ ] **Step 1: Create the canonical template**

Copy the existing content to the new location:

```bash
mkdir -p lib/clm/templates
cp tests/fixtures/fix-perms.sh lib/clm/templates/fix-perms.sh
chmod +x lib/clm/templates/fix-perms.sh
rm tests/fixtures/fix-perms.sh
```

- [ ] **Step 2: Update all four test files' reference path**

In each of `tests/clm_install_test.bats`, `tests/vault_cmd_test.bats`, `tests/unpack_test.bats`, `tests/vault_fixperms_script_test.bats`, replace every occurrence of:

```
$BATS_TEST_DIRNAME/fixtures/fix-perms.sh
```

with:

```
$BATS_TEST_DIRNAME/../lib/clm/templates/fix-perms.sh
```

(Note `vault_fixperms_script_test.bats` currently references it as `$BATS_TEST_DIRNAME/fixtures/fix-perms.sh` too, not `../fixtures/` — verify the exact existing string per file with `grep -n fixtures/fix-perms.sh tests/*.bats` before replacing, since paths must resolve correctly relative to each test file's own location in `tests/`.)

- [ ] **Step 3: Run the full suite to confirm no regressions**

Run: `bats tests/`
Expected: 0 failures — this step only moves a file, no behavior change.

- [ ] **Step 4: Commit**

```bash
git add lib/clm/templates/fix-perms.sh tests/clm_install_test.bats tests/vault_cmd_test.bats tests/unpack_test.bats tests/vault_fixperms_script_test.bats
git rm tests/fixtures/fix-perms.sh
git commit -m "Move fix-perms.sh template to lib/clm/templates/ (real runtime resource, not test-only)"
```

---

## Task 2: `clm settings new`

**Files:**
- Create: `lib/clm/settings.sh`
- Modify: `bin/clm` (source it, add `settings` noun, update usage)
- Create: `tests/settings_test.bats`

**Interfaces:**
- Produces: `cmd_settings_new(machine_name, from_machine)`.

- [ ] **Step 1: Write the failing tests**

Create `tests/settings_test.bats`:

```bash
#!/usr/bin/env bats

load 'test_helper'

setup() {
  setup_clm_env
}

@test "clm settings new refuses when cl-settings root doesn't exist" {
  run env CLM_ROOT="$CLM_ROOT" CLM_MACHINE_NAME="new-machine" "$CLM_ROOT/bin/clm" settings new
  [ "$status" -ne 0 ]
  [[ "$output" == *"cl-settings not found"* ]]
}

@test "clm settings new refuses when the target machine folder already exists" {
  mkdir -p "$CLM_ROOT/cl-settings/new-machine"
  run env CLM_ROOT="$CLM_ROOT" CLM_MACHINE_NAME="new-machine" "$CLM_ROOT/bin/clm" settings new
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "clm settings new scaffolds an empty skeleton for the current machine with no --from" {
  mkdir -p "$CLM_ROOT/cl-settings"
  run env CLM_ROOT="$CLM_ROOT" CLM_MACHINE_NAME="new-machine" "$CLM_ROOT/bin/clm" settings new
  [ "$status" -eq 0 ]
  [ -d "$CLM_ROOT/cl-settings/new-machine/dotfiles" ]
  [ -x "$CLM_ROOT/cl-settings/new-machine/vault/bin/fix-perms.sh" ]
  [ -d "$CLM_ROOT/cl-settings/new-machine/vault/global/ssh/keys" ]
  [ -d "$CLM_ROOT/cl-settings/new-machine/pack" ]
  [ -z "$(ls -A "$CLM_ROOT/cl-settings/new-machine/dotfiles")" ]
}

@test "clm settings new copies dotfiles from --from and fixes up the ssh config's machine path" {
  mkdir -p "$CLM_ROOT/cl-settings/old-machine/dotfiles/zsh" "$CLM_ROOT/cl-settings/old-machine/dotfiles/ssh/.ssh"
  echo 'export FOO=1' > "$CLM_ROOT/cl-settings/old-machine/dotfiles/zsh/.zshrc"
  cat > "$CLM_ROOT/cl-settings/old-machine/dotfiles/ssh/.ssh/config" <<'EOF'
Include ~/clm/cl-settings/old-machine/vault/global/ssh/config
Include ~/clm/cl-settings/old-machine/vault/projects/*/ssh/config

Host *
    IdentitiesOnly yes
EOF

  run env CLM_ROOT="$CLM_ROOT" CLM_MACHINE_NAME="new-machine" "$CLM_ROOT/bin/clm" settings new new-machine --from old-machine
  [ "$status" -eq 0 ]
  [ -f "$CLM_ROOT/cl-settings/new-machine/dotfiles/zsh/.zshrc" ]
  grep -q "cl-settings/new-machine/vault/global/ssh/config" "$CLM_ROOT/cl-settings/new-machine/dotfiles/ssh/.ssh/config"
  grep -q "cl-settings/new-machine/vault/projects" "$CLM_ROOT/cl-settings/new-machine/dotfiles/ssh/.ssh/config"
  ! grep -q "old-machine" "$CLM_ROOT/cl-settings/new-machine/dotfiles/ssh/.ssh/config"
  [ ! -e "$CLM_ROOT/cl-settings/new-machine/vault/global/ssh/keys/id_rsa" ]
}

@test "clm settings new refuses when --from source machine doesn't exist" {
  mkdir -p "$CLM_ROOT/cl-settings"
  run env CLM_ROOT="$CLM_ROOT" CLM_MACHINE_NAME="new-machine" "$CLM_ROOT/bin/clm" settings new new-machine --from nonexistent-machine
  [ "$status" -ne 0 ]
  [[ "$output" == *"nonexistent-machine"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/settings_test.bats`
Expected: FAIL — `clm` doesn't recognize the `settings` noun yet.

- [ ] **Step 3: Implement `lib/clm/settings.sh`**

```bash
#!/usr/bin/env bash

CLM_TEMPLATES_DIR="${CLM_TEMPLATES_DIR:-$CLM_ROOT/lib/clm/templates}"

cmd_settings_new() {
  local machine_name="${1:-$CLM_MACHINE_NAME}"
  local from_machine="$2"
  local cl_settings_root="$CLM_ROOT/cl-settings"
  local target="$cl_settings_root/$machine_name"

  [ -d "$cl_settings_root" ] || clm::die "cl-settings not found at $cl_settings_root (clone it first)"
  [ ! -d "$target" ] || clm::die "cl-settings/$machine_name already exists"

  local source=""
  if [ -n "$from_machine" ]; then
    source="$cl_settings_root/$from_machine"
    [ -d "$source/dotfiles" ] || clm::die "cl-settings/$from_machine not found"
  fi

  mkdir -p "$target/dotfiles" "$target/vault/global/ssh/keys" "$target/vault/projects" "$target/vault/bin" "$target/pack"

  if [ -n "$from_machine" ]; then
    local entry
    for entry in "$source/dotfiles"/*; do
      [ -e "$entry" ] || continue
      cp -R "$entry" "$target/dotfiles/"
    done
    if [ -f "$target/dotfiles/ssh/.ssh/config" ]; then
      sed -i '' "s#cl-settings/$from_machine/#cl-settings/$machine_name/#g" "$target/dotfiles/ssh/.ssh/config"
    fi
    echo "settings: copied dotfiles from $from_machine"
  fi

  cp "$CLM_TEMPLATES_DIR/fix-perms.sh" "$target/vault/bin/fix-perms.sh"
  chmod +x "$target/vault/bin/fix-perms.sh"
  cat > "$target/vault/global/ssh/config" <<'EOF'
# Host blocks for keys that should always be available, regardless of project.
# Example:
#
# Host github.com-personal
#     HostName github.com
#     User git
#     IdentityFile ~/clm/cl-settings/<machine>/vault/global/ssh/keys/id_ed25519_personal
EOF
  touch "$target/vault/global/ssh/keys/.gitkeep" "$target/vault/projects/.gitkeep"
  cat > "$target/vault/README.md" <<EOF
# vault ($machine_name)

Private secrets for this machine. Add real SSH keys under
global/ssh/keys/ or projects/<name>/ssh/keys/, then run:
clm vault fix-perms
EOF

  echo "settings: created cl-settings/$machine_name"
  cat <<EOF

Next steps:
  # add real SSH keys under cl-settings/$machine_name/vault/global/ssh/keys/
  clm vault fix-perms
  clm stow onboard
EOF
}
```

- [ ] **Step 4: Wire `settings` into `bin/clm`**

Add to the source block:

```bash
# shellcheck source=lib/clm/settings.sh
source "$CLM_ROOT/lib/clm/settings.sh"
```

Update `usage()`:

```bash
usage() {
  cat <<'EOF'
Usage: clm <noun> <verb> [args] [--yes]

Nouns:
  stow      onboard | add <pkg> | remove <pkg> | list
  vault     fix-perms
  status
  pack      list | all | brew | mas | vscode | cursor | npm | pnpm
  unpack
  settings  new [machine-name] [--from <source-machine>]
EOF
}
```

Add to the `case "$noun" in ... esac` block:

```bash
    settings)
      verb="${1:-}"
      [ "$#" -gt 0 ] && shift
      case "$verb" in
        new)
          target_name=""
          from_machine=""
          while [ "$#" -gt 0 ]; do
            case "$1" in
              --from) from_machine="${2:-}"; shift 2 ;;
              *) target_name="$1"; shift ;;
            esac
          done
          cmd_settings_new "$target_name" "$from_machine"
          ;;
        *) usage; exit 1 ;;
      esac
      ;;
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bats tests/settings_test.bats`
Expected: `5 tests, 0 failures`

- [ ] **Step 6: Run the full suite to confirm no regressions**

Run: `bats tests/`
Expected: 0 failures.

- [ ] **Step 7: Commit**

```bash
git add lib/clm/settings.sh bin/clm tests/settings_test.bats
git commit -m "Add clm settings new: scaffold a new machine's cl-settings folder"
```

---

## Task 3: README update

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add `clm settings new` to the commands list and a short new-machine note**

Add to `## \`clm\` commands`:

```markdown
    clm settings new [name] [--from <machine>]  # scaffold a new machine's cl-settings folder
```

Add a new subsection after `## First-time setup on a new machine`'s content:

```markdown
### Setting up an additional (not-yet-seen) machine

`cl-settings` is namespaced per machine (`cl-settings/<machine-name>/`).
If this is a genuinely new machine — not a reinstall of one already in
`cl-settings` — `clm unpack` will correctly say `cl-settings not found`
for *this* machine's subfolder, even though `cl-settings` itself cloned
fine. Scaffold it first:

    clm settings new --from <existing-machine-name>
    clm unpack

`--from` copies that machine's dotfiles as an editable starting point.
`vault/` and `pack/` always start empty — add real SSH keys yourself
under `cl-settings/<this-machine>/vault/`, then run `clm vault fix-perms`.
```

- [ ] **Step 2: Run the full test suite one more time**

Run: `bats tests/`
Expected: all tests pass, `0 failures`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document clm settings new for onboarding additional machines"
```
