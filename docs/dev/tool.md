# The device tool: design notes

[English](tool.md) | [中文](tool.zh-CN.md)

This records the rules `bin/omp-termux` implements and why they exist. The commands a user runs are in
[the README](../../README.md); the other half is [the build half](build.md).

## Two halves, one set of names

`bin/omp-termux` is the device side: `install`, `status`, `verify` and `doctor` act on the pi-natives of the
machine that runs them, and `help`, `update-self` and `uninstall-self` work anywhere. `dev/omp-termux-dev` sources
the tool, so the addon's file name, the repository, the version helpers and the reporting helpers exist once; its
own dispatch is the only thing that runs a verb when the file is executed.

## What the tool owns

- Its own copy: `~/.local/opt/omp-termux`, linked from `$PREFIX/bin` on Termux, else `$XDG_BIN_HOME` or
  `~/.local/bin`. `uninstall-self` removes both. A new copy is staged beside the old one and renamed over it.
- Scratch: `$OMP_TERMUX_CACHE_HOME`, else `$XDG_CACHE_HOME/omp-termux`, else `~/.cache/omp-termux`. Only
  `install` and `verify` open it; every run gets its own `run.<pid>` directory, removed on exit. The directory
  belongs to the tool alone: only the run directory is removed recursively, the root only with `rmdir` when empty.
- The self-update cache: `$PREFIX/cache/self-update`, under the prefix so `uninstall-self` takes it away with the
  rest.

## The environment is resolved once

`resolve_env` is the only writer of `BIN_HOME`, `CACHE_HOME`, `TMP_HOME`, `BUN_DEFAULT`, `BUN_ROOTS`, `BUN_HOME`,
`BUN_BIN` and `OMP_BIN`; every function below takes its inputs as arguments or reads those. `scratch_open` sets
`SCRATCH` for the two verbs that use it. A step that changes the environment (installing bun or omp) calls
`resolve_env` again, and nothing else re-derives a path.

bun's install root follows bun's own rule: `BUN_INSTALL`, else `$XDG_CACHE_HOME/.bun`, else `~/.bun`. Every root
that exists is visited in that order, with `$HOME/.cache/.bun` last: it is bun's XDG-era layout, reachable only
through `XDG_CACHE_HOME`, so it is visited after the roots bun's own rule names. A relative value is ignored —
bun's global install dies with `EACCES` under one — and so is a scratch path that resolves to `/` or `$HOME`.

The root in use is the first one carrying `@oh-my-pi/pi-coding-agent`, else the first existing root, else bun's
default. The shell is pinned there (`BUN_INSTALL`, `PATH`) because bun installs where `BUN_INSTALL` points, not
where `PATH` does.

The build half does not repeat this rule: it uploads the tool and asks its `status` for the `omp` row.

## The scratch directory

`OMP_TERMUX_CACHE_HOME`, else `$XDG_CACHE_HOME/omp-termux`, else `~/.cache/omp-termux` holds one directory per
installation, named `run.<pid>`, created by `install` and `verify` only. A dead directory (its process is gone) is
reclaimed when the next run opens its own; a live one is left alone, so two runs can overlap. The run's files —
the downloaded addon, the loader probe, the verify log — never outlive the run: the EXIT trap removes the
directory, and the now-empty cache root too. The addon download is written into that directory, so a partial file
cannot be mistaken for a complete one.

## What the device loads

`natives_dirs` lists every installed `@oh-my-pi/pi-natives` under the bun roots' cache (both layouts) and the
global tree, deduplicated by real path: the Termux repair below makes one package reachable under several
spellings. bun is the install contract; npm's global trees are not searched.

The copy the loader resolves is the one in `<root>/install/global/node_modules`; a root without it falls back to
the newest package it holds. The loader skips its release check when the path has no `node_modules` segment (a
workspace load) and otherwise compares `__piNativesBuildVersion()` with the package version, which is why an addon
is only put into a package carrying its own release.

An addon's release is readable from a 64-byte slot stamped after linking (`PI_NATIVES_VERSION_STAMP:<version>`);
releases before that slot exported a per-release napi name instead (`__piNativesV18_3_2`). Both are accepted,
because a device can still hold a pre-stamp copy.

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

A local file is provisioned exactly like a version: it is not a shortcut that skips omp. `cmd_install` then:

1. repairs the Termux layout and reads what is installed;
2. records the newest release here in the self-update cache, so `status` does not keep a stale value;
3. when the target is already in place and loads, drops stale global entries, reports `nothing to do` and exits 0
   without a download;
4. refuses a target it picked itself when the omp the device runs is newer than anything published here — after
   the current check, so a run that changes nothing never refuses on the way;
5. gets the addon before it touches omp: the release is downloaded into this run's scratch directory (its stamp
   must name the target), a local file is used as given;
6. installs bun when missing, installs the CLI at the target, and raises bun to the installed omp's `engines.bun`
   floor — an omp that needs a newer bun cannot start, so this happens before the addon lands;
7. installs the addon into every matching package (copy beside the destination, then rename), verifies the loaded
   copy quietly, prunes strictly older copies from bun's cache (never through a symlink), and installs the tool
   itself;
8. reports `omp <version> ready (<n> addon copies)` with the leftover count appended when there is one.

Progress (`fetching pi-natives <ver> for android-arm64`, `installing omp <ver>`, `installing the addon`) goes to
stderr; the one result line goes to stdout.

The order exists to avoid a device that cannot start omp: the addon is in hand before omp is replaced, and bun is
raised to the floor before the addon is touched. A refused or failed run leaves the manifest and the tree alone.
The addon lands through `stage_into`: copy to `<dst>.part.<pid>`, rename over the destination. The tool's own
copy is staged beside it and renamed the same way, as `update-self` does.

## Status and verification

`status` writes rows to stdout only:

```
tool      omp-termux v0.6.0 (adf4d632b9e2)
omp       18.18.3
addon     18.18.3  105 MB loaded
          18.18.0  105 MB leftover
newest    omp-18.18.3
paths     bun   ~/.bun
          omp   ~/.bun/bin/omp
          tool  ~/.local/opt/omp-termux/omp-termux
```

`tool` is the tool label, `omp` is the CLI version (`none` when absent) — the build half parses exactly this row,
`addon` rows carry every installed copy with its size, `newest` appears when the release cache holds one, and
`paths` collapses `$HOME` to `~` unless `OMP_TERMUX_VERBOSE=1`.

`verify` writes one row per addon, then one for the CLI:

```
addon  18.18.3  android-arm64  154 exports  ok (loaded)
addon  18.18.0  ok (leftover)
omp    18.18.3  starts         ok
```

It finishes with `omp-termux: verify ok`. Row output goes to stdout; progress (`==> ...`), warnings and errors go
to stderr. `check_addons` loads the resolved copy and every leftover through bun and checks the export set, but
prints at most two leftover rows (a failing one always prints; `OMP_TERMUX_VERBOSE=1` lists them all)
(the modules Android trims are expected absent), but only the copy the loader resolves can fail the run: a
leftover package of another release need not carry an addon for this platform. `run_verify` then runs
`omp --version`; `omp` is whatever the user installed, never the tool's. A failed loaded copy is reported with its
directory; in the install path the hint points at `omp-termux verify`.

## Self-update and the release lookups

`check_self_update` runs before every verb except `help` and `update-self`, and only from the installed copy. It
fetches `main`, compares the SHA-256 of the body with its own, caches the result under
`$PREFIX/cache/self-update` for `OMP_TERMUX_UPDATE_TTL` seconds, and prints one progress line to stderr when they
differ; there is no conditional request and no `ETag`. The cache is keyed to the copy that fetched it: a tool
replaced by other means re-checks instead of reporting a difference that does not exist. The same file holds the
newest release here, which `status` shows; an install that resolved a release writes it back.

`update-self` fetches the script, runs `bash -n`, compares hashes, and only then renames the new copy over the old
one; an identical body reports `already up to date`.

Every request goes through one helper, `http URL OUT MAX`: one `curl -fsSL` invocation with `--retry 3`,
`--connect-timeout 15` and `--max-time MAX`, which prints `<status> <effective URL>`. A 404/4xx/5xx status is
classified by the caller; `000` or an empty status is a network failure. Release lookups read the redirect of
`https://github.com/<repo>/releases/latest` instead of the GitHub API: 60 requests per hour are per IP, and a
phone behind carrier NAT shares that with strangers.

The egress is exhaustive: `raw.githubusercontent.com/<repo>/main/...` (bootstrap and self-update),
`github.com/<repo>/releases/latest` (redirect lookup), `github.com/<upstream>/releases/latest` (the build half's
target), `github.com/<repo>/releases/download/omp-<ver>/...` (the addon),
`github.com/oven-sh/bun/releases/latest/download/bun-linux-aarch64-android.zip` (bun), the build half's
`github.com/<upstream>.git` clone with `patch-diff.githubusercontent.com/raw/<upstream>/pull/6350.diff` as the
patch fallback, and ssh/scp to `OMP_TERMUX_HOST`. No identifier, analytics or telemetry is sent.

## Environment knobs

`OMP_TERMUX_REPO`, `OMP_TERMUX_RELEASE_BASE`, `OMP_TERMUX_RAW_BASE`, `OMP_TERMUX_CACHE_HOME`, `OMP_TERMUX_VERSION`,
`OMP_TERMUX_NO_UPDATE_CHECK`, `OMP_TERMUX_UPDATE_TTL` and `OMP_TERMUX_VERBOSE` for the tool; `OMP_TERMUX_NDK`,
`OMP_TERMUX_MODE`, `OMP_TERMUX_HOST` and `OMP_TERMUX_PORT` for the build half. Defaults cover a bare device, so no
export is required.
