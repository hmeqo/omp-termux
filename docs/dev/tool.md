# The device tool

[English](tool.md) | [中文](tool.zh-CN.md)

`bin/omp-termux` installs the Android addon into the pi-natives package `omp` uses, and keeps omp and the addon at
the same version. This page records the rules it implements; the commands are in [the README](../../README.md), the
build and release in [build.md](build.md).

## What the tool owns

- Its own copy: `~/.local/opt/omp-termux`, linked from `$TERMUX_PREFIX/bin` on Termux, else `$XDG_BIN_HOME` or
  `~/.local/bin`. `uninstall-self` removes both. A new copy is staged beside the old one and renamed over it.
- Scratch: `OMP_TERMUX_CACHE_HOME`, else `$XDG_CACHE_HOME/omp-termux`, else `~/.cache/omp-termux`. Only `install`
  and `verify` open it; each run gets a `run.<pid>` directory removed by an EXIT trap, and the root goes with it
  once empty. Opening reclaims a directory whose process is gone and leaves a live one alone. The addon is
  downloaded inside it, so a partial file cannot be mistaken for a complete one.
- The self-update cache: `~/.local/opt/omp-termux/cache/self-update`, so `uninstall-self` takes it away with the rest.

## Environment

`resolve_env` is the only reader of `HOME`, `XDG_*`, `BUN_INSTALL` and `PATH`, and the only writer of the resolved
variables; a step that installs bun or omp calls it again. Everything else takes arguments or reads them.

bun's root follows bun's own rule: `BUN_INSTALL`, else `$XDG_CACHE_HOME/.bun`, else `~/.bun`; the older
`~/.cache/.bun` root is still searched, last. A relative value is ignored — bun's global install fails with `EACCES`
under one — as is a scratch path that resolves to `/` or `$HOME`.

The root in use is the first carrying `@oh-my-pi/pi-coding-agent`, else the first existing one, else bun's default.
The shell is pinned there (`BUN_INSTALL`, `PATH`), because bun installs where `BUN_INSTALL` points, not where `PATH`
does.

## What the device loads

`natives_dirs` lists every installed `@oh-my-pi/pi-natives` under every bun root — its `install/cache` and
`install/global` trees — deduplicated by real path. The loader resolves `<root>/install/global/node_modules`; a root
without that falls back to its newest package. It compares an addon's release with the package version, which is why
an addon only goes into a package carrying its own release.

An addon reports its release from a 64-byte slot stamped after linking (`PI_NATIVES_VERSION_STAMP:<version>`), or
from a per-release napi name on older builds (`__piNativesV18_3_2`). Both are accepted.

`bun install -g` leaves `<root>/bin/omp` resolving into `<root>/install/cache/<pkg>@<version>@@@1`, where no
`node_modules` exists, so lazily imported packages fail (`omp stats` cannot find the addon) while the rest of the
CLI starts. `link_global_tree` links each global package into `<cache>/node_modules`; it refreshes symlinks and
leaves a real directory alone, because `ln -sfn` into a directory links inside it.

## install

The target is resolved in this order:

| argument | target |
|---|---|
| a `.node` file | that artifact; its own reported version is the target |
| a version | that version, even when ahead of what is published |
| `latest` | the newest release here; the installed version, with a warning, when the lookup fails |
| none | `$OMP_TERMUX_VERSION`, else the version the device runs; the newest release here when it runs none |

`cmd_install` then:

1. links bun's global packages into its cache tree (`link_global_tree`) and reads what is installed;
2. resolves the target, recording the newest release here in the self-update cache so `status` is not stale;
3. when the target is in place, its addon loads and `omp` starts, drops stale global entries and reports
   `nothing to do` without a download;
4. refuses a target it picked itself when the omp the device runs is newer than anything published here;
5. gets the addon before it touches omp: the release is downloaded into scratch and must report the target version,
   and a local file must report a readable version too;
6. installs bun when missing, the CLI at the target, and raises bun to the installed omp's `engines.bun` floor;
7. installs the addon into every matching package (a copy beside the destination, then rename), verifies the loaded
   copy quietly, prunes strictly older copies from bun's cache, and installs the tool itself;
8. reports `omp <version> ready (<n> addon copies)`, with the leftover count when there is one.

Progress (`fetching pi-natives <ver> for android-arm64`, `installing omp <ver>`, `installing the addon`) goes to
stderr; the result line goes to stdout. The order keeps a failed download from touching an existing install: the
addon is in hand before omp is replaced, and bun reaches its floor before the addon lands. A refused target or a
failed download changes nothing.

## status and verify

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

`tool` is the tool label, `omp` is the CLI version (`none` when absent) — the build script reads this row.
`addon` rows carry every installed copy with its size, `newest` appears when the release cache holds one, and
`paths` collapses `$HOME` to `~` unless `OMP_TERMUX_VERBOSE=1`.

`verify` writes one row per addon, then one for the CLI:

```
addon  18.18.3  android-arm64  154 exports  ok (loaded)
addon  18.18.0  ok (leftover)
omp    18.18.3  starts         ok
```

It ends with `omp-termux: verify ok`. Rows go to stdout; progress (`==> ...`), warnings and errors go to stderr.
`check_addons` loads the resolved copy and every leftover through bun and checks the export set (the modules Android
trims are expected absent). It prints at most two leftover rows plus an
`addon  +N more leftovers (OMP_TERMUX_VERBOSE=1 lists them)` line; a failing leftover always prints, and
`OMP_TERMUX_VERBOSE=1` lists every row with its export count. Only the resolved copy can fail the run: a leftover of
another release need not carry an addon for this platform. `run_verify` then runs the `omp` the user has (from
`PATH`, else bun's roots), warns when it is not `$BUN_HOME/bin/omp`, and fails when it does not start. A failed copy
is reported with its directory; an install failure suggests `omp-termux verify`.

`doctor` writes `termux`, `uname`, `tool`, `bun`, `omp`, `addon` and `free` rows to stdout, and warns when bun is
missing.

## Self-update and release lookups

`check_self_update` runs before every verb except `help` and `update-self`, and only from the installed copy. It
fetches `main`, compares the SHA-256 of the body with its own, caches the result under its own
`cache/self-update` for `OMP_TERMUX_UPDATE_TTL` seconds, and prints one line to stderr on every run while they
differ. The cache records the hash of the copy that wrote it, so a tool replaced by other means re-checks instead of
reporting a stale difference. The same file holds the newest release here, which `status` shows; an install that
resolved a release writes it back.

`update-self` fetches the script, runs `bash -n`, compares hashes, and only then renames the new copy over the old
one; an identical body reports `already up to date`.

Every request goes through one helper, `http URL OUT MAX`: one `curl -fsSL` call with `--retry 3`,
`--connect-timeout 15` and `--max-time MAX`, printing `<status> <effective URL>`. Callers classify 404/4xx/5xx by
status; `000` or an empty status is a network failure. Release lookups follow the redirect of
`https://github.com/<repo>/releases/latest` instead of the GitHub API, whose 60 requests per hour are per IP and
shared by a phone behind carrier NAT.

## Environment variables

`OMP_TERMUX_REPO`, `OMP_TERMUX_RELEASE_BASE`, `OMP_TERMUX_RAW_BASE`, `OMP_TERMUX_VERSION`,
`OMP_TERMUX_NO_UPDATE_CHECK`, `OMP_TERMUX_UPDATE_TTL` and `OMP_TERMUX_VERBOSE` for the tool; `OMP_TERMUX_CACHE_HOME`
sets the tool's scratch root and the build script's upload directory; `OMP_TERMUX_NDK`, `OMP_TERMUX_MODE`,
`OMP_TERMUX_HOST` and `OMP_TERMUX_PORT` for the build script. Defaults cover a fresh device, so no export is
required.
