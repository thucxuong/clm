# clm unpack: Extensions + npm/pnpm Globals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `clm unpack` also restores VS Code/Cursor extensions and npm/pnpm globals from `clm pack`'s captured files, per the addendum in `docs/superpowers/specs/2026-07-15-clm-settings-consolidation-design.md`.

**Architecture:** Four new functions in `lib/clm/unpack.sh` (`clm::unpack_npm`, `clm::unpack_pnpm`, `clm::unpack_vscode`, `clm::unpack_cursor`), each independently skippable, called at the end of `cmd_unpack`.

**Tech Stack:** Bash (bash 3.2 compatible), bats-core.

## Global Constraints

- Same bash 3.2 constraints as prior plans (no associative arrays, etc.).
- Every restore step is independently skippable: absent pack file → skip with a message, tool not installed → skip with a message. Neither is an error.
- Versions are never pinned on restore — always install latest (`npm install -g <name>`, `pnpm add -g <name>`, no version suffix), consistent with "keep dev tools current" rather than "freeze at capture time."

---

## Task 1: npm and pnpm global restore

**Files:**
- Modify: `lib/clm/unpack.sh`
- Modify: `tests/unpack_test.bats`

**Interfaces:**
- Produces: `clm::unpack_npm()`, `clm::unpack_pnpm()` — each reads its pack file under `$CLM_SETTINGS_DIR/pack/`, skips gracefully if the file is absent or the tool isn't on `PATH`, otherwise parses package names and calls `npm install -g <name>` / `pnpm add -g <name>` per package.

- [ ] **Step 1: Write the failing tests**

Append to `tests/unpack_test.bats`:

```bash

@test "clm unpack restores npm globals, correctly stripping scoped and unscoped versions" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh" "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"
  cat > "$settings_dir/pack/npm-global.txt" <<'EOF'
/Users/x/.nvm/versions/node/v22.14.0/lib
├── @google/gemini-cli@
├── clerk@1.5.0
└── vercel@54.14.2
EOF
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  ln -s "$(command -v stow)" "$FAKE_BIN/stow"
  cat > "$FAKE_BIN/npm" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "install" ] && [ "\$2" = "-g" ]; then
  echo "npm install -g \$3" >> "$BATS_TEST_TMPDIR/npm-calls.log"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/npm"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  grep -q "npm install -g @google/gemini-cli$" "$BATS_TEST_TMPDIR/npm-calls.log"
  grep -q "npm install -g clerk$" "$BATS_TEST_TMPDIR/npm-calls.log"
  grep -q "npm install -g vercel$" "$BATS_TEST_TMPDIR/npm-calls.log"
}

@test "clm unpack skips npm restore gracefully when npm-global.txt is absent" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh" "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  [[ "$output" == *"no npm-global.txt found"* ]]
}

@test "clm unpack skips npm restore gracefully when npm is not installed" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh" "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"
  echo "clerk@1.5.0" > "$settings_dir/pack/npm-global.txt"
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  ln -s "$(command -v stow)" "$FAKE_BIN/stow"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  [[ "$output" == *"npm not installed"* ]]
}

@test "clm unpack restores pnpm globals from the dependencies section only" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh" "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"
  cat > "$settings_dir/pack/pnpm-global.txt" <<'EOF'
Legend: production dependency, optional only, dev only

/Users/x/Library/pnpm/global/5

dependencies:
@google/gemini-cli 0.20.2
aws-cdk 2.1027.0
EOF
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  ln -s "$(command -v stow)" "$FAKE_BIN/stow"
  cat > "$FAKE_BIN/pnpm" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "add" ] && [ "\$2" = "-g" ]; then
  echo "pnpm add -g \$3" >> "$BATS_TEST_TMPDIR/pnpm-calls.log"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/pnpm"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  grep -q "pnpm add -g @google/gemini-cli$" "$BATS_TEST_TMPDIR/pnpm-calls.log"
  grep -q "pnpm add -g aws-cdk$" "$BATS_TEST_TMPDIR/pnpm-calls.log"
  ! grep -q "Legend" "$BATS_TEST_TMPDIR/pnpm-calls.log"
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/unpack_test.bats`
Expected: FAIL — `clm::unpack_npm`/`clm::unpack_pnpm` don't exist yet.

- [ ] **Step 3: Implement `clm::unpack_npm` and `clm::unpack_pnpm` in `lib/clm/unpack.sh`**

```bash
clm::unpack_npm() {
  local file="$CLM_SETTINGS_DIR/pack/npm-global.txt"
  [ -f "$file" ] || { echo "no npm-global.txt found — skipping npm globals"; return 0; }
  command -v npm >/dev/null 2>&1 || { echo "npm not installed — skipping npm globals"; return 0; }
  local line name
  while IFS= read -r line; do
    case "$line" in
      *"├──"*|*"└──"*)
        name="$(echo "$line" | sed -E 's/^[^a-zA-Z0-9@]+//')"
        name="${name%@*}"
        [ -n "$name" ] || continue
        npm install -g "$name" || clm::die "npm install -g $name failed"
        echo "npm: installed $name"
        ;;
    esac
  done < "$file"
}

clm::unpack_pnpm() {
  local file="$CLM_SETTINGS_DIR/pack/pnpm-global.txt"
  [ -f "$file" ] || { echo "no pnpm-global.txt found — skipping pnpm globals"; return 0; }
  command -v pnpm >/dev/null 2>&1 || { echo "pnpm not installed — skipping pnpm globals"; return 0; }
  local line name in_deps=0
  while IFS= read -r line; do
    if [ "$line" = "dependencies:" ]; then
      in_deps=1
      continue
    fi
    [ "$in_deps" = "1" ] || continue
    [ -n "$line" ] || continue
    name="${line%% *}"
    [ -n "$name" ] || continue
    pnpm add -g "$name" || clm::die "pnpm add -g $name failed"
    echo "pnpm: installed $name"
  done < "$file"
}
```

Add calls in `cmd_unpack`, after the `brew bundle` block:

```bash
  clm::unpack_npm
  clm::unpack_pnpm
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/unpack_test.bats`
Expected: all pass, including the 4 new ones.

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `bats tests/`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/clm/unpack.sh tests/unpack_test.bats
git commit -m "clm unpack: restore npm/pnpm globals from pack output"
```

---

## Task 2: VS Code and Cursor extension restore

**Files:**
- Modify: `lib/clm/unpack.sh`
- Modify: `tests/unpack_test.bats`

**Interfaces:**
- Produces: `clm::unpack_vscode()`, `clm::unpack_cursor()` — each reads its pack file, skips gracefully if absent or the editor's CLI isn't installed, otherwise installs each extension.

- [ ] **Step 1: Write the failing tests**

Append to `tests/unpack_test.bats`:

```bash

@test "clm unpack restores vscode extensions one per line" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh" "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"
  printf 'alefragnani.bookmarks\nangular.ng-template\n' > "$settings_dir/pack/vscode-extensions.txt"
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  ln -s "$(command -v stow)" "$FAKE_BIN/stow"
  cat > "$FAKE_BIN/code" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "--install-extension" ]; then
  echo "code --install-extension \$2" >> "$BATS_TEST_TMPDIR/code-calls.log"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/code"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  grep -q "code --install-extension alefragnani.bookmarks" "$BATS_TEST_TMPDIR/code-calls.log"
  grep -q "code --install-extension angular.ng-template" "$BATS_TEST_TMPDIR/code-calls.log"
}

@test "clm unpack skips vscode restore gracefully when code is not installed" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh" "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"
  echo "alefragnani.bookmarks" > "$settings_dir/pack/vscode-extensions.txt"
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  ln -s "$(command -v stow)" "$FAKE_BIN/stow"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  [[ "$output" == *"code not installed"* ]]
}

@test "clm unpack restores cursor extensions one per line" {
  mkdir -p "$CLM_DOTFILES_DIR/zsh" "$CLM_VAULT/global/ssh/keys" "$CLM_VAULT/bin"
  echo 'x' > "$CLM_DOTFILES_DIR/zsh/.zshrc"
  cp "$BATS_TEST_DIRNAME/fixtures/fix-perms.sh" "$CLM_VAULT/bin/fix-perms.sh"
  chmod +x "$CLM_VAULT/bin/fix-perms.sh"
  settings_dir="$CLM_ROOT/settings"
  mkdir -p "$settings_dir/pack"
  printf 'alefragnani.bookmarks\n' > "$settings_dir/pack/cursor-extensions.txt"
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  ln -s "$(command -v stow)" "$FAKE_BIN/stow"
  cat > "$FAKE_BIN/cursor" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "--install-extension" ]; then
  echo "cursor --install-extension \$2" >> "$BATS_TEST_TMPDIR/cursor-calls.log"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKE_BIN/cursor"

  run env CLM_ROOT="$CLM_ROOT" CLM_TARGET="$CLM_TARGET" CLM_DOTFILES_DIR="$CLM_DOTFILES_DIR" CLM_VAULT="$CLM_VAULT" CLM_SETTINGS_DIR="$settings_dir" PATH="$FAKE_BIN:/usr/bin:/bin" "$CLM_ROOT/bin/clm" unpack
  [ "$status" -eq 0 ]
  grep -q "cursor --install-extension alefragnani.bookmarks" "$BATS_TEST_TMPDIR/cursor-calls.log"
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/unpack_test.bats`
Expected: FAIL — `clm::unpack_vscode`/`clm::unpack_cursor` don't exist yet.

- [ ] **Step 3: Implement `clm::unpack_vscode` and `clm::unpack_cursor` in `lib/clm/unpack.sh`**

```bash
clm::unpack_vscode() {
  local file="$CLM_SETTINGS_DIR/pack/vscode-extensions.txt"
  [ -f "$file" ] || { echo "no vscode-extensions.txt found — skipping VS Code extensions"; return 0; }
  command -v code >/dev/null 2>&1 || { echo "code not installed — skipping VS Code extensions"; return 0; }
  local ext
  while IFS= read -r ext; do
    [ -n "$ext" ] || continue
    code --install-extension "$ext" || clm::die "code --install-extension $ext failed"
  done < "$file"
  echo "vscode: extensions restored"
}

clm::unpack_cursor() {
  local file="$CLM_SETTINGS_DIR/pack/cursor-extensions.txt"
  [ -f "$file" ] || { echo "no cursor-extensions.txt found — skipping Cursor extensions"; return 0; }
  command -v cursor >/dev/null 2>&1 || { echo "cursor not installed — skipping Cursor extensions"; return 0; }
  local ext
  while IFS= read -r ext; do
    [ -n "$ext" ] || continue
    cursor --install-extension "$ext" || clm::die "cursor --install-extension $ext failed"
  done < "$file"
  echo "cursor: extensions restored"
}
```

Add calls in `cmd_unpack`, after `clm::unpack_pnpm`:

```bash
  clm::unpack_vscode
  clm::unpack_cursor
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/unpack_test.bats`
Expected: all pass.

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `bats tests/`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/clm/unpack.sh tests/unpack_test.bats
git commit -m "clm unpack: restore VS Code/Cursor extensions from pack output"
```

---

## Task 3: README update

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the `## What's not here yet` section and the `clm unpack` description**

Change:

```markdown
- `clm unpack` only restores dotfiles, vault, and brew (CLI tools + apps).
  Restoring VS Code/Cursor extensions or npm/pnpm globals from their pack
  files is still manual.
```

to:

```markdown
- Restoring App Store apps (`mas`) from their pack file — brew's own mas
  integration in the Brewfile already covers most cases, so this is low
  priority.
```

Update the `clm unpack` line in `## \`clm\` commands`:

```markdown
    clm unpack                   # stow onboard + vault fix-perms + brew bundle + npm/pnpm globals + vscode/cursor extensions, from cl-settings
```

- [ ] **Step 2: Run the full test suite one more time**

Run: `bats tests/`
Expected: all tests pass, `0 failures`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document npm/pnpm/extension restore in clm unpack"
```
