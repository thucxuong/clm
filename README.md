# clm — Chris Luu Machine

This repo is the engine only — no personal data lives here. It's the `clm`
CLI plus the GNU Stow/Homebrew/gh mechanics needed to rehydrate a machine
from your actual settings, which live in a separate repo, `cl-settings`.

## First-time setup on a new machine

    curl -fsSL https://raw.githubusercontent.com/thucxuong/clm/main/bootstrap.sh | sh -s -- you/your-settings-repo

That's it — one command. It clones `~/clm`, then hands off to
`clm-install.sh`: Homebrew, Stow, and `gh` get installed if missing,
`gh auth login` runs if you're not already authenticated (browser-based —
no SSH key needed), `cl-settings` gets cloned if it isn't already present,
and `clm unpack` runs at the end (stow onboard + vault fix-perms + brew
bundle + npm/pnpm globals + VS Code/Cursor extensions). Every step checks
its own precondition first, so if this gets interrupted partway (network
blip, closed terminal mid-`gh auth login`), just run the same command
again — nothing gets redone unnecessarily, and it picks up wherever it
left off.

`clm` itself goes on `PATH` via a line `clm-install.sh` adds to
`~/.zshenv` (not via Homebrew, and not via `cl-settings`/Stow either) —
zsh reads `.zshenv` on every invocation, so this is set up before
anything that could fail (like `cl-settings` not yet having a folder for
a brand-new machine) has a chance to block it. Open a new terminal after
the first run for that to take effect.

Prefer to inspect before piping to `sh`? The equivalent two-step version:

    git clone https://github.com/thucxuong/clm.git ~/clm
    cd ~/clm && ./clm-install.sh thucxuong/cl-settings

If you don't have the repo slug handy yet, `./clm-install.sh` (no argument)
still installs Homebrew/Stow/gh and authenticates `gh`; it stops with a
clear message at the `cl-settings not found` step, telling you exactly
what to run once you do have it.

This deliberately avoids SSH for the first clone — `gh auth login` is
browser-based OAuth, so no SSH key is needed just to get `cl-settings`
(which is where your SSH keys actually live). SSH only becomes usable
after `clm unpack` has run.

### Setting up an additional (not-yet-seen) machine

`cl-settings` is namespaced per machine (`cl-settings/<machine-name>/`).
If this is a genuinely new machine — not a reinstall of one already in
`cl-settings` — `clm unpack` will correctly say `cl-settings not found`
for *this* machine's subfolder, even though `cl-settings` itself cloned
fine. `clm-install.sh` will already have added `clm` to `~/.zshenv`
before that failure though, so **open a new terminal first**, then:

    clm settings new --from <existing-machine-name>
    clm-install.sh thucxuong/cl-settings

(Re-running `clm-install.sh` is resumable — it skips everything already
done and picks up at `clm unpack`, which now succeeds.) `--from` copies
that machine's dotfiles as an editable starting point. `vault/` always
starts empty — add real SSH keys yourself under
`cl-settings/<this-machine>/vault/`, then run `clm vault fix-perms`.

## Layout

- `bin/clm` — the CLI. `lib/clm/*.sh` holds one module per noun.
- `clm-install.sh` — one-time bootstrap (Homebrew, Stow, gh, puts `clm` on PATH).
- `cl-settings/` — a separate, private, gitignored nested git repo holding
  your actual settings, namespaced per machine:
  `cl-settings/<machine-name>/{dotfiles,vault,pack}`. Clone it independently
  via `gh repo clone`; it's never part of this repo's history.
  - `dotfiles/` — the GNU Stow packages (`zsh/`, `bash/`, `git/`, `ssh/`).
  - `vault/` — SSH keys and config, global and per-project.
  - `pack/` — captured machine-state manifests (Brewfile, extension lists,
    etc.), produced by `clm pack`.

## `clm` commands

    clm stow onboard          # stow zsh, bash, git, ssh in one shot
    clm stow add <package>    # stow one package
    clm stow remove <package> # unstow one package (asks for confirmation)
    clm stow list             # show stow state of every package
    clm vault fix-perms       # fix key file/dir permissions in cl-settings/<machine>/vault
    clm status                # stow + vault health check
    clm pack list              # show which pack checkers are available here
    clm pack all                # capture everything available, then archive the whole ~/clm tree
    clm pack <checker>          # capture one source, e.g. `clm pack brew`
    clm unpack                   # stow onboard + vault fix-perms + brew bundle + npm/pnpm globals + vscode/cursor extensions, from cl-settings
    clm settings new [name] [--from <machine>]  # scaffold a new machine's cl-settings folder

Every subcommand accepts `--yes` to skip confirmation prompts.

## Safety

- Stow conflicts (an existing non-symlink file at a target path) are
  detected via a dry-run before every real `stow` call. The conflicting
  file is renamed to `<name>.clm-backup` (never clobbering an earlier
  backup — `.clm-backup.1`, `.clm-backup.2`, ... if needed) and the real
  stow retries — nothing is ever deleted, and nothing is silently
  overwritten either. `--no-folding` is always passed so a not-yet-existing
  target directory (like `~/.ssh`) gets its individual files symlinked
  rather than becoming one directory-level symlink.
- `clm stow remove` and the Homebrew install step in `clm-install.sh` prompt
  for confirmation unless `--yes`/`CLM_YES=1` is set.
- All permission fixes (`clm vault fix-perms`) touch only the specific,
  named key directories — never a blanket recursive chmod over `~/clm` or
  `cl-settings/<machine>/vault`.
- `clm unpack` refuses (rather than guessing) when `cl-settings` hasn't been
  cloned yet.
- `clm unpack`'s `brew bundle` step installs casks (GUI apps) into
  `~/Applications` rather than the shared `/Applications`, so it never
  needs admin-group write access.

## Backups

`clm pack all` finishes by archiving the entire `~/clm` tree (which
includes `cl-settings/`, and therefore your dotfiles, vault, and the pack
output it just generated) into a single timestamped `.tar.gz` under
`~/clm-backups/` (override with `CLM_BACKUP_DIR`). This archive is **not
encrypted** — it contains real SSH private keys in plaintext, so treat the
resulting file with the same care as the keys themselves (e.g. only copy it
to storage that's already encrypted).

## Tests

    bats tests/

Requires `bats-core` (`brew install bats-core`). All tests run against
temporary directories via `CLM_ROOT`/`CLM_TARGET`/`CLM_DOTFILES_DIR`/
`CLM_VAULT`/`CLM_SETTINGS_DIR` overrides, and use fixture copies of
generic content (`tests/fixtures/`) rather than reading real, personal
`cl-settings` data — they never touch the real `$HOME`, a real Homebrew
installation, or your actual settings.

## What's not here yet

- Restoring App Store apps (`mas`) from their pack file — brew's own mas
  integration in the Brewfile already covers most cases, so this is low
  priority.
- Vaulting tool-managed auth (`gh`, `vercel`, `npm login`, Docker registry).
- Per-project "active project" switching for single-file configs (`.npmrc`,
  `.env`, docker-compose) — the planned project hub, a future `clm project`
  namespace.

See `docs/superpowers/specs/2026-07-15-clm-foundation-design.md`,
`docs/superpowers/specs/2026-07-15-clm-pack-design.md`, and
`docs/superpowers/specs/2026-07-15-clm-settings-consolidation-design.md`
for the full design rationale.
