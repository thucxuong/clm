# clm pack: Machine State Capture ("packingup")

Status: Approved for planning
Date: 2026-07-15

## Context

This is the second subsystem built on the [CLM foundation](2026-07-15-clm-foundation-design.md).
Where the foundation manages dotfiles/secrets that are hand-authored, `clm pack`
answers a different question: "what's currently installed/configured on this
machine, captured in a form I can look at (and eventually restore from) on a
new machine?" The user calls this "packing up" — like packing before a move.

Restoring/reinstalling from these captured manifests on a new machine (an
`clm unpack` or similar) is explicitly out of scope for this spec — it's a
natural follow-up once packing itself is proven.

## Goals

- A `clm pack` namespace, following the existing dispatcher pattern.
- Modular "checkers," one per source (Homebrew, Mac App Store, VS Code/Cursor
  extensions, npm/pnpm globals). Each checker detects whether its tool exists
  on this machine before doing anything — running an unavailable checker is a
  harmless no-op, not an error.
- Output is plain, human-readable/tool-native manifest files committed to the
  public `~/clm` repo (not vault — package/app names aren't secrets).
- `clm pack list` — show every checker and whether it's available here.
- `clm pack <checker>` — run one checker.
- `clm pack all` — run every checker, skipping unavailable ones.

## Non-goals (deferred)

- Restoring/reinstalling from the captured manifests on a new machine.
- Deduplicating overlap between `brew`'s Mac App Store integration (which
  `brew bundle dump` includes automatically when `mas` is present) and the
  standalone `mas` checker — both are kept, since they're independent,
  low-cost, plain-text captures, not executable state.
- Capturing macOS system/app preferences (`defaults read` domains) — noisier
  and more machine-specific; a possible future checker, not part of this pass.

## Design

### Checkers (first pass)

| Checker | Availability check | Capture command | Output file |
|---|---|---|---|
| `brew` | `command -v brew` | `brew bundle dump --force --file=<out>` | `pack/Brewfile` |
| `mas` | `command -v mas` | `mas list` | `pack/mas.txt` |
| `vscode` | `command -v code` | `code --list-extensions` | `pack/vscode-extensions.txt` |
| `cursor` | `command -v cursor` | `cursor --list-extensions` | `pack/cursor-extensions.txt` |
| `npm` | `command -v npm` | `npm ls -g --depth=0` | `pack/npm-global.txt` |
| `pnpm` | `command -v pnpm` | `pnpm list -g --depth=0` | `pack/pnpm-global.txt` |

Output directory is `$CLM_ROOT/pack/`, overridable via a `CLM_PACK_DIR`
environment variable (mirroring `CLM_TARGET`/`CLM_VAULT`) so tests never
write into the real repo.

### Module: `lib/clm/pack.sh`

Following the same shape as `stow.sh`/`vault.sh` — no associative arrays
(bash 3.2 compatibility), a fixed case-statement registry instead:

- `clm::pack_checkers()` — prints the six checker names, one per line.
- `clm::pack_available(checker)` — returns 0/1 based on the checker's
  availability check.
- `clm::pack_run(checker)` — runs the checker's capture command, writes its
  output file, prints `packed: <checker> -> <path>`. Assumes the checker is
  already known to be available (callers check first).
- `cmd_pack_list()` — iterates checkers, printing `<name> [available]` or
  `<name> [not present]`.
- `cmd_pack_one(checker)` — validates the checker name, prints
  `skip (not present): <checker>` and returns 0 if unavailable, otherwise
  calls `clm::pack_run`.
- `cmd_pack_all()` — calls `cmd_pack_one` for every checker in the registry.

### CLI wiring

`bin/clm` gains a `pack` noun:

```
clm pack list
clm pack <checker>
clm pack all
```

Consistent with `stow`/`vault`/`status`, `pack` is added to the existing
`case "$noun" in ... esac` block and to the `usage()` text.

### Safety

No confirmation prompts are needed for `pack` commands: every write is
scoped to `$CLM_PACK_DIR` (never anywhere else), every output file is
git-tracked (so any overwrite is recoverable from history via `git diff`/
`git checkout`), and nothing here touches installed software, only reads
its current state.

## Migration / usage

```sh
clm pack all          # capture everything available on this machine
git -C ~/clm add pack && git -C ~/clm commit -m "Update machine pack"
```

On a new machine, `pack/Brewfile` can already be consumed directly via
`brew bundle --file=pack/Brewfile` even before a dedicated `clm unpack`
command exists — the other manifests are for now read as reference.
