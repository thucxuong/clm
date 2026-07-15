# cl-settings Consolidation and clm unpack

Status: Approved for planning
Date: 2026-07-15

## Context

Building `clm pack` surfaced a real bootstrapping problem: SSH is needed to
clone `vault` (for the SSH keys), but SSH keys are what live in `vault` —
circular. The resolution is to stop relying on SSH for the *first* clone at
all: authenticate with `gh auth login` (browser OAuth, no keys needed) and
clone over HTTPS.

That only works cleanly if everything needed to rehydrate a machine —
dotfiles, vault (with real keys), and pack output — comes from ONE
`gh`-clonable repo. Today they're split: dotfiles live inside the `clm`
engine repo itself, `vault` is a separate nested repo, and `pack/` is
gitignored noise. This spec consolidates all three into one new repo,
`cl-settings`, and adds `clm unpack` to rehydrate a machine from it.

This supersedes:
- The vault design in [CLM foundation](2026-07-15-clm-foundation-design.md)
  (vault stops being its own standalone nested repo).
- The `pack/` tracking decision in the
  [clm pack addendum](2026-07-15-clm-pack-design.md#addendum-2026-07-15-gitignore-pack-and-a-full-machine-archive)
  (pack output moves under cl-settings and is tracked there, per-machine).

## Goals

- `~/clm` becomes purely the CLI engine (`bin/clm`, `lib/clm/*.sh`,
  `clm-install.sh`) — no personal data.
- `~/clm/cl-settings/` is ONE repo (nested, gitignored by the outer `clm`
  repo — same pattern `vault/` used before) holding, per machine:
  ```
  cl-settings/<machine-name>/
    dotfiles/   (zsh/, bash/, git/, ssh/ — the existing Stow packages)
    vault/      (global/, projects/ — the existing vault content, real keys included)
    pack/       (Brewfile, mas.txt, extension lists, npm/pnpm globals)
  ```
  Per-machine namespacing applies uniformly to all three — dotfiles and
  vault are not assumed identical across machines.
- Machine name is auto-detected via `scutil --get ComputerName`, overridable
  via `CLM_MACHINE_NAME` (needed for tests, and for anyone who wants a
  different label than their computer's display name).
- `clm-install.sh` also ensures `gh` is installed (another Homebrew
  formula, alongside the existing Stow check).
- A new `clm unpack` command rehydrates the *current* machine from an
  already-cloned `cl-settings`: stow-onboards the dotfiles, fixes vault
  permissions, and `brew bundle`s the packed Brewfile — in that order.

## Non-goals (deferred)

- `clm unpack` does not perform the `gh repo clone` itself — cloning
  `cl-settings` is a manual prerequisite step (documented in the README),
  consistent with how `clm vault fix-perms` already assumes vault is
  pre-cloned rather than cloning it itself.
- Restoring VS Code/Cursor extensions or npm/pnpm globals as part of
  `clm unpack` — only the Brewfile (CLI tools + apps) is restored in this
  pass; the other pack files remain reference-only for now.
- Multi-machine settings sync/merge tooling (e.g. "copy machine A's dotfiles
  to machine B") — out of scope; each machine's folder is independent.

## Design

### Directory structure

```
~/clm/                            (engine repo — bin/clm, lib/clm/*.sh, clm-install.sh, README, docs/)
  .gitignore                       # adds "cl-settings/" (vault/ entry removed — no longer used)
  cl-settings/                     (separate nested repo, gitignored by outer clm repo)
    <machine-name>/
      dotfiles/
        zsh/.zshrc
        bash/.bash_profile, .profile
        git/.gitconfig, .config/git/ignore
        ssh/.ssh/config
      vault/
        global/ssh/{config, keys/}
        projects/<name>/ssh/{config, keys/}
        bin/fix-perms.sh
      pack/
        Brewfile
        mas.txt, vscode-extensions.txt, cursor-extensions.txt,
        npm-global.txt, pnpm-global.txt
```

### Environment variables (renamed/repointed)

Today `CLM_ROOT` serves double duty: it's both "where the `clm` engine
lives" (used to find `lib/clm/*.sh`) and "the Stow package directory." These
diverge now that dotfiles moves under `cl-settings/<machine>/dotfiles`. New
variables:

- `CLM_ROOT` — unchanged meaning: where the engine (`bin/clm`, `lib/clm/`)
  lives. Still resolved via symlink-following in `bin/clm`.
- `CLM_MACHINE_NAME` — new. Default: `scutil --get ComputerName`.
- `CLM_SETTINGS_DIR` — new. Default: `$CLM_ROOT/cl-settings/$CLM_MACHINE_NAME`.
- `CLM_DOTFILES_DIR` — new. Default: `$CLM_SETTINGS_DIR/dotfiles`. Replaces
  every use of `$CLM_ROOT` as the Stow package directory in `lib/clm/stow.sh`.
- `CLM_TARGET` — unchanged: the Stow *target* (default `$HOME`).
- `CLM_VAULT` — repointed. Default becomes `$CLM_SETTINGS_DIR/vault`
  (was `$CLM_ROOT/vault`).
- `CLM_PACK_DIR` — repointed. Default becomes `$CLM_SETTINGS_DIR/pack`
  (was `$CLM_ROOT/pack`).
- `CLM_BACKUP_DIR` — unchanged: `$HOME/clm-backups`. The archive still tars
  the whole `$CLM_ROOT` tree, which now includes `cl-settings/` (nested,
  present on disk even though gitignored by the outer repo) — no change
  needed to `clm::pack_archive` itself.

### Module changes

- `lib/clm/stow.sh` — every `$CLM_ROOT` reference becomes `$CLM_DOTFILES_DIR`
  (`clm::stow_packages`, `clm::is_stowed`, `clm::validate_package`,
  `cmd_stow_add`, `cmd_stow_remove`, `cmd_stow_onboard`). The
  `CLM_STOW_EXCLUDE` mechanism (`vault bin lib docs .git`) is removed
  entirely: `CLM_DOTFILES_DIR` is now a directory that, by construction,
  only ever contains actual packages (`vault`/`pack` are siblings under
  `cl-settings/<machine>/`, not inside `dotfiles/`), so the exclusion check
  has nothing left to guard against. `clm::validate_package` becomes a
  plain existence check.
- `lib/clm/vault.sh` — no logic changes; `CLM_VAULT`'s new default handles
  the repointing.
- `lib/clm/pack.sh` — no logic changes; `CLM_PACK_DIR`'s new default handles
  the repointing.
- `lib/clm/common.sh` — add `clm::machine_name()`, returning
  `${CLM_MACHINE_NAME:-$(scutil --get ComputerName)}`. Add
  `CLM_SETTINGS_DIR`/`CLM_DOTFILES_DIR` default computation (mirroring how
  `CLM_VAULT`/`CLM_PACK_DIR` already compute their defaults from `CLM_ROOT`).
- `bin/clm` — exports `CLM_MACHINE_NAME`, `CLM_SETTINGS_DIR`,
  `CLM_DOTFILES_DIR` alongside the existing exports. Adds the `unpack` noun.
- `clm-install.sh` — `ensure_gh()`, mirroring `ensure_stow()`: if `gh` isn't
  found, `brew install gh`. Called alongside `ensure_stow` in `main`.

### `clm unpack`

```
cmd_unpack() {
  [ -d "$CLM_SETTINGS_DIR" ] || clm::die "cl-settings not found at $CLM_SETTINGS_DIR (clone it first: gh repo clone <you>/cl-settings ...)"
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

Order matters: dotfiles/vault first (so `~/.ssh`, `~/.gitconfig`, etc. are
in place), then software install last (some formulae/casks may want to read
config that's now in place, e.g. git-related tooling).

### New-machine bootstrap flow (end to end)

```sh
git clone <clm-engine-repo-url> ~/clm
cd ~/clm && ./clm-install.sh        # Homebrew, Stow, gh, links `clm` globally
gh auth login                        # browser OAuth — no SSH needed
gh repo clone <you>/cl-settings ~/clm/cl-settings
clm unpack                           # stow onboard + vault fix-perms + brew bundle
```

### Safety

Unchanged principles from the foundation/pack specs apply: `clm unpack`
refuses (via `clm::die`) rather than guessing when `cl-settings` isn't
present; `cmd_stow_onboard`/`cmd_vault_fix_perms` keep their existing
conflict-refusal and scoped-permission behavior; nothing new here bypasses
Stow's native conflict detection.

## Migration of existing content

The current real repo has dotfiles directly at its root and a standalone
`vault/` nested repo. This spec migrates them:

1. `mkdir -p cl-settings/$(scutil --get ComputerName)/{dotfiles,vault,pack}`
2. Move `zsh/`, `bash/`, `git/`, `ssh/` → `cl-settings/<machine>/dotfiles/`
3. Move `vault/`'s contents (not its `.git` — the old standalone vault repo's
   one-commit history isn't worth preserving separately) →
   `cl-settings/<machine>/vault/`
4. `cl-settings/` becomes its own fresh git repo (`git init`), replacing the
   old standalone `vault/` repo's role.
5. Update `.gitignore`: remove `vault/`, add `cl-settings/`.
6. Update all existing tests (`stow_test.bats`, `dispatch_test.bats`,
   `vault_cmd_test.bats`, `status_test.bats`, `pack_test.bats`,
   `pack_dispatch_test.bats`, `ssh_package_test.bats`, `test_helper.bash`)
   to set up the new nested structure instead of a flat one.
