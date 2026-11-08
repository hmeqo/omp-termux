# The device tool: design notes

[English](tool.md) | [中文](tool.zh-CN.md)

This records the rules `bin/omp-termux` implements and why they exist. The commands a user runs are in
`README.md`; the other half is `build.md`.

## Two halves, one set of names

`bin/omp-termux` is the device side: `install`, `status`, `verify` and `doctor` act on the pi-natives of the
machine that runs them, and `help`, `update-self` and `uninstall-self` work anywhere. `dev/omp-termux-dev` sources
the tool, so the addon's file name, the repository and the reporting helpers exist once; its own dispatch is the
only thing that runs a verb when the file is executed.

## What the tool owns

- Its own copy: `~/.local/opt/omp-termux`, linked from `$PREFIX/bin` on Termux, else `$XDG_BIN_HOME` or
  `~/.local/bin`. `uninstall-self` removes both.
- Scratch: `$OMP_TERMUX_CACHE_HOME`, else `$XDG_CACHE_HOME/omp-termux`, else `~/.cache/omp-termux`. Downloads,
  probes and logs go there and are removed afterwards. The directory belongs to the tool alone, so a stale one is
  cleared file by file, never with a recursive delete.
- The self-update check: `$PREFIX/cache/self-update`, under the prefix so `uninstall-self` takes it away with the
  rest.

## The environment is resolved once

`resolve_env` reads `BUN_INSTALL`, `XDG_*`, `HOME` and `PATH`; every verb below reads only what it set. A step that
changes the environment (installing bun or omp) calls it again, and nothing else re-derives a path.

bun's install root follows bun's own rule: `BUN_INSTALL`, else `$XDG_CACHE_HOME/.bun`, else `~/.bun`. Every root
that exists is visited in that order, with `$HOME/.cache/.bun` last: it is bun's XDG-era layout, reachable only
through `XDG_CACHE_HOME`, so it is visited after the roots bun's own rule names. A relative value is ignored — bun's
global install dies with `EACCES` under one — and so is a scratch path that resolves to `/` or `$HOME`.

The root in use is the first one carrying `@oh-my-pi/pi-coding-agent`, else the first existing root, else bun's
default. The shell is pinned there (`BUN_INSTALL`, `PATH`) because bun installs where `BUN_INSTALL` points, not
where `PATH` does.

The build half runs commands on the device before it can upload the tool, so the same rule exists as a POSIX
snippet (`REMOTE_ROOT_PROBE`) the device evaluates itself. `tests/verify.sh` compares the two answers.

## What the device loads

`natives_dirs` lists every installed `@oh-my-pi/pi-natives` under the bun root's cache (both layouts), the bun
global tree and npm's global trees, deduplicated by real path: the Termux repair below makes one package reachable
under several spellings.

The copy the loader resolves is the one in `<root>/install/global/node_modules`; a root without it falls back to
the newest package it holds. The loader skips its release check when the path has no `node_modules` segment (a
workspace load) and otherwise compares `__piNativesBuildVersion()` with the package version, which is why an addon
is only put into a package carrying its own release.

An addon's release is readable from a 64-byte slot stamped after linking
(`PI_NATIVES_VERSION_STAMP:<version>`); releases before that slot exported a per-release napi name instead
(`__piNativesV18_3_2`). Both are accepted, because a device can still hold a pre-stamp copy.

## Termux's bun layout

`bun install -g` leaves `<root>/bin/omp` resolving into `<root>/install/cache/<pkg>@<version>@@@1`, where no
`node_modules` exists, so lazily imported packages fail (`omp stats` cannot find `@oh-my-pi/pi-natives`) while the
rest of the CLI starts. `link_global_tree` links each global package into `<cache>/node_modules`; it refreshes
symlinks and leaves a real directory alone, because `ln -sfn` into a directory links inside it.

## The install verb

The target is resolved in this order:

| argument | target |
|---|---|
| a `.node` file | that artifact; its own stamp is the version |
| a version | that version, the caller's call even when it is ahead of what is published |
| `latest` | the newest release here; the installed version, with a warning, when the lookup fails |
| none | `$OMP_TERMUX_VERSION`, else the version the device runs; the newest release here when it runs none |

`device_install` then, in order:

1. repairs the Termux layout and reads what is installed;
2. records the newest release here in the self-update cache, so `status` does not keep a stale value;
3. when the target is already in place and loads, drops stale global entries, reports and exits 0 without a
   download;
4. refuses a target it picked itself when the omp the device runs is newer than anything published here — after
   the current check, so a run that changes nothing never refuses on the way;
5. installs bun when missing, fetches the addon (its stamp must name the target), drops the stale global entries,
   installs the CLI, and names the addon's package on the install line when the tree is off target — then removes
   that pin again, so the manifest keeps the CLI alone and its exact pins decide the tree;
6. raises bun to the installed omp's `engines.bun` floor — an omp that needs a newer bun cannot start, so this
   happens before the addon lands;
7. installs the addon into every matching package (`.part` then rename), verifies, prunes strictly older copies
   from bun's cache (never through a symlink), and installs the tool itself.

The order exists to avoid a device that cannot start omp: the addon is fetched before omp is replaced, and bun is
raised to the floor before the addon is touched. A refused or failed run leaves the manifest and the tree alone.

## Status and verification

`run_verify` loads every installed package's `native/index.js` through bun and checks the export set (the modules
Android trims are expected absent), but only the copy the loader resolves can fail the run: a leftover package of
another release need not carry an addon for this platform. It then runs `omp --version`; `omp` is whatever the user
installed, never the tool's.

## Self-update and the release lookups

`check_self_update` runs before every verb except `help` and `update-self`, and only from the installed copy. It
compares the SHA-256 of `main` with its own through a conditional GET (`ETag`), caches the result under
`$PREFIX/cache/self-update` for `OMP_TERMUX_UPDATE_TTL` seconds, and prints one line to stderr when they differ.
The cache is keyed to the copy that fetched it: a tool replaced by other means re-checks instead of reporting a
difference that does not exist. The same file holds the newest release here, which `status` shows; an install that
resolved a release writes it back.

Both release lookups read the `Location` header of `https://github.com/<repo>/releases/latest` (the tag suffix is
stripped) instead of the GitHub API: 60 requests per hour are per IP, and a phone behind carrier NAT shares that
with strangers.
