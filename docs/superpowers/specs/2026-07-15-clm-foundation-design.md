# CLM Foundation: Dotfiles, Vault, and CLI

Status: Approved for planning
Date: 2026-07-15

## Context

This repo (currently `~/machine-setup`, to be renamed `~/clm` — "Chris Luu Machine")
is the first of several planned subsystems for managing a personal dev machine:

1. **CLM foundation** (this spec) — dotfiles, secrets ("vault"), and the `clm` CLI
2. App/CLI tool installer (Homebrew casks + CLI tools) — future spec
3. Deeper per-tool secrets integration (gh, vercel, npm, docker) — future spec
4. Project/experiment environment hub (spin up/tear down project-scoped tooling,
   including Docker Compose) — future spec

Subsystems 2–4 are out of scope here but the structure below is designed so they
plug in as new top-level namespaces under `clm` without requiring a rework of
what's built now.

An existing `~/dotfiles` repo already has a working GNU Stow setup (`zsh`, `bash`,
`git` packages). This spec supersedes it: that content moves into the new `~/clm`
structure described below (the repo itself is renamed/relocated, not recreated from
scratch, so git history is preserved).

## Goals

- A single directory (`~/clm`) that is the answer to "everything about how my
  machine is set up lives here."
- SSH keys and per-project SSH access organized in a private, git-tracked-but-not-
  public "vault," structured for easy migration to a new machine.
- Tools that support it (SSH) work with zero manual per-project registration.
- A `clm` CLI that abstracts away the mechanics (Stow flags, permissions, symlinks)
  behind a small number of intuitive, namespaced commands.
- A shared safety layer so that as more commands get added over time, dangerous
  actions (data loss, clobbering unrelated files) are structurally hard to trigger
  by accident.

## Non-goals (deferred to future specs)

- Installing macOS apps/CLI tools (Homebrew casks, `pnpm`, `gh`, `vercel`, etc.)
- Vaulting tool-managed auth stores (`gh`, `vercel`, `npm login`, Docker registry
  auth) — these are left as "log in again on a new machine" for now.
- Per-project "active project" switching for single-file configs (`.npmrc`, `.env`,
  git identity, docker-compose) — this is the job of the future project hub.

## Directory structure

```
~/clm/                       (git repo — the renamed/relocated ~/dotfiles)
  .git/
  .gitignore                  # includes "vault/" and ".DS_Store"
  README.md                   # umbrella doc; explains CLM, links to vault/README.md
  clm-install.sh               # one-time bootstrap, see below
  bin/
    clm                        # the CLI dispatcher (bash), see below
  zsh/.zshrc
  bash/.bash_profile, .profile
  git/.gitconfig, .config/git/ignore
  ssh/.ssh/config              # Stow package; content is just:
      # Include ~/clm/vault/global/ssh/config
      # Include ~/clm/vault/projects/*/ssh/config
      # Host *
      #     IdentitiesOnly yes
  vault/                       (separate nested git repo, private, gitignored by outer repo)
    README.md
    global/
      ssh/
        config                 # Host blocks for always-on keys (personal GitHub, servers)
        keys/                  # actual key files; dir chmod 700, files chmod 600
    projects/
      <project-name>/
        ssh/
          config               # Host blocks specific to this project
          keys/
        # reserved for future subsystems: env/, npmrc, etc. — not populated by this spec
    bin/
      fix-perms.sh             # chmod 700 on key dirs, 600 on key files; scoped, not recursive-blind
```

### Why this shape

- **Stow needs zero extra flags.** `~/clm` sits directly under `$HOME`, so Stow's
  default target (parent of the directory you run it from) is already `~`.
  `clm stow onboard` works the same way `stow zsh bash git` does today.
- **`vault/` is a separate nested git repo**, excluded via `~/clm/.gitignore`, so it
  can have different remote/visibility (private, or no remote — local + manual
  backup) without ever touching the public dotfiles repo's history, and without
  Stow ever treating it as a package (see Safety layer below).
- **SSH `Include` with a glob** (`projects/*/ssh/config`) means every project's SSH
  hosts are picked up automatically — no manual registration, and no "which
  project is active" concept needed for SSH, since SSH natively supports many
  simultaneous identities via `Host` blocks. Verified empirically: a missing
  `Include` target (single path or unmatched glob) fails silently rather than
  erroring, so this also works correctly on a fresh machine before `vault/` has
  been cloned.
- **The `projects/<name>/` convention is reserved now** even though only `ssh/` is
  populated, so the future project hub can add `env/`, `npmrc`, etc. under the same
  per-project folder without restructuring.

## Bootstrap: `clm-install.sh`

Run once per machine, after cloning:

```sh
git clone <clm-repo-url> ~/clm
cd ~/clm && ./clm-install.sh
```

Steps, in order, each idempotent (safe to re-run):

1. Check for Homebrew; if missing, run the official Homebrew install script
   (after a confirmation prompt — see Safety layer).
2. Check for `stow`; if missing, `brew install stow`.
3. `chmod +x ~/clm/bin/clm`
4. `ln -sf ~/clm/bin/clm "$(brew --prefix)/bin/clm"` — this makes `clm` globally
   callable immediately (Homebrew's bin dir is already on `PATH`), no shell
   restart or rc file edits needed.
5. Print next steps: run `clm stow onboard`, and if you have vault access, clone
   the vault repo to `~/clm/vault`.

## The `clm` CLI

`~/clm/bin/clm` is a bash dispatcher using noun-then-verb subcommands, so future
subsystems become new nouns (`clm install ...`, `clm project ...`) without
touching what's built here.

Initial `stow` namespace:

| Command | Behavior |
|---|---|
| `clm stow onboard` | Stows the standard package set (`zsh bash git ssh`) in one shot — the "just cloned this, set it all up" command |
| `clm stow add <package>` | Stows one additional package by name |
| `clm stow remove <package>` | Unstows (`stow -D`) a package |
| `clm stow list` | Lists stowable packages (subfolders of `~/clm`, excluding `vault` and `bin`) and whether each is currently stowed |

Cross-cutting:

| Command | Behavior |
|---|---|
| `clm status` | Health check: which packages are stowed, whether `~/clm/vault` exists, whether vault key permissions are correct |
| `clm vault fix-perms` | Runs the scoped perms-fix logic over `~/clm/vault/**/keys` |

## Safety layer

Every `clm` subcommand goes through shared guardrails rather than each
reimplementing safety logic ad hoc:

- **Confirm before anything destructive or irreversible** (e.g. `clm stow remove`,
  running the Homebrew installer, anything that would overwrite existing content).
  A `--yes` flag skips prompts for scripted/non-interactive use.
- **Refuse on unexpected state** instead of guessing or forcing through it — e.g.
  if a Stow target path already exists and isn't a symlink into the expected
  package, stop and report it rather than overwriting; if `~/clm/vault` already
  exists and has content before a clone step, stop rather than merging/clobbering.
- **Scoped operations only.** Any `chmod`/`rm` touches explicitly named, narrow
  paths (e.g. `vault/global/ssh/keys`, `vault/projects/*/ssh/keys`) — never a
  blanket recursive operation across `~/clm` or `~/clm/vault` as a whole.
- **`vault` and `bin` are never stowable.** `clm stow list`/`onboard` hard-exclude
  them from the package set, so there's no path by which `vault/`'s contents (or
  the CLI's own script) get symlinked wholesale into `$HOME` by accident.

This layer is additive: as subsystems 2–4 add commands, they get these guarantees
for free rather than each needing its own safety review.

## Migration to a new machine (end-to-end)

```sh
git clone <clm-repo-url> ~/clm
cd ~/clm && ./clm-install.sh      # bootstraps Homebrew/Stow, installs `clm` globally
clm stow onboard                  # symlinks zsh/bash/git/ssh into $HOME
git clone <vault-repo-url> ~/clm/vault
clm vault fix-perms                # fixes key file/dir permissions
```

SSH access works immediately after this; no further manual wiring needed.
