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
- `pack/` — captured machine-state manifests (Brewfile, extension lists, etc.),
  produced by `clm pack`. Gitignored — regenerable, not worth tracking.

## `clm` commands

    clm stow onboard          # stow zsh, bash, git, ssh in one shot
    clm stow add <package>    # stow one package
    clm stow remove <package> # unstow one package (asks for confirmation)
    clm stow list             # show stow state of every package
    clm vault fix-perms       # fix key file/dir permissions in ~/clm/vault
    clm status                # stow + vault health check
    clm pack list              # show which pack checkers are available here
    clm pack all                # capture everything available, then archive the whole ~/clm tree
    clm pack <checker>          # capture one source, e.g. `clm pack brew`

Every subcommand accepts `--yes` to skip confirmation prompts.

## Safety

- Stow conflicts (an existing non-symlink file at a target path) are refused
  natively by GNU Stow — nothing here overrides that. `--no-folding` is always
  passed so a not-yet-existing target directory (like `~/.ssh`) gets its
  individual files symlinked rather than becoming one directory-level symlink.
- `clm stow remove` and the Homebrew install step in `clm-install.sh` prompt
  for confirmation unless `--yes`/`CLM_YES=1` is set.
- All permission fixes (`clm vault fix-perms`) touch only the specific,
  named key directories — never a blanket recursive chmod over `~/clm` or
  `~/clm/vault`.

## Backups

`clm pack all` finishes by archiving the entire `~/clm` tree (dotfiles,
vault, and the pack output it just generated) into a single timestamped
`.tar.gz` under `~/clm-backups/` (override with `CLM_BACKUP_DIR`). This
archive is **not encrypted** — it contains real SSH private keys in
plaintext, so treat the resulting file with the same care as the keys
themselves (e.g. only copy it to storage that's already encrypted).

## Tests

    bats tests/

Requires `bats-core` (`brew install bats-core`). All tests run against
temporary directories via `CLM_ROOT`/`CLM_TARGET`/`CLM_VAULT` overrides —
they never touch the real `$HOME` or a real Homebrew installation.

## What's not here yet

- Restoring/reinstalling from `clm pack`'s captured manifests on a new
  machine (a future `clm unpack`).
- Vaulting tool-managed auth (`gh`, `vercel`, `npm login`, Docker registry).
- Per-project "active project" switching for single-file configs (`.npmrc`,
  `.env`, docker-compose) — the planned project hub, a future `clm project`
  namespace.

See `docs/superpowers/specs/2026-07-15-clm-foundation-design.md` and
`docs/superpowers/specs/2026-07-15-clm-pack-design.md` for the full design
rationale.
