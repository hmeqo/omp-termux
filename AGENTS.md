# Repository Guidelines

## Project Overview

`omp-termux` makes `omp` (the oh-my-pi coding agent) run on Android aarch64 / Termux. Upstream publishes no Android
build of `@oh-my-pi/pi-natives`, so `omp` aborts with `Unsupported platform: android-arm64`. This repo supplies that
addon — cross-compiled from upstream with the vendored PR #6350 patch, or prebuilt from its releases — and installs it into the
package the user has. `omp` is never rebuilt; the tool has bun install it at the matching version.

## Architecture

`bin/omp-termux` is the device tool: it reports and repairs whatever pi-natives the machine that runs it holds, and
`install`, `status`, `verify` and `doctor` answer for that machine. `dev/omp-termux-dev` builds the addon and drives
a target device over ssh. Both are single bash files organized in sections introduced by a `# --- name ---` banner;
`dev/omp-termux-dev` sources the tool for the names both need, and the tool's dispatch is guarded by
`if [ "${BASH_SOURCE[0]}" = "$0" ]`, so sourcing runs nothing.

| Section | Contents |
|---|---|
| constants, output | `TERMUX_PREFIX`, `PREFIX`, `SELF`, `ADDON`, `VERIFY_LOG`, `PROBE_JS`, `UPSTREAM_REPO`, `REPO`, `TOOL_VERSION`, `PROG`, `PARENT_PATH`, `SELF_URL`, `SELF_CACHE`, `SELF_TTL`, `BUN_URL`; `msg`, `result`, `warn`, `print_error`, `err`, `die`, `have`, `usage` |
| state, environment | `resolve_env` (the only writer, inert at source time), `absolute_dir`, `bun_default_root`, `existing_bun_roots`, `bun_roots`, `bun_root_in_use`, `bin_home_dir`, `cache_home_dir`, `bun_binary_path`, `omp_binary_path`, `use_root` |
| scratch, fs, http | `scratch_open`, `scratch_reap`; `stage_into`, `http`, `reject_option`, `require_file_arg`, `json_version`, `file_sha`, `tmp_dir`, `version_min/max/ge/gt/lt`, `same_path` |
| installed, release | `search_roots`, `natives_dirs`, `newest_natives_dir`, `installed_state`, `is_workspace_load`, `artifact_version`, `latest_release_version`, `latest_version`, `fetch_release` |
| bun, omp tree | `download_bun`, `device_ensure_bun`, `upgrade_bun`, `cli_bun_floor`, `ensure_bun_for_omp`, `stray_scope_deps`, `drop_stray_scope_deps`, `install_addon`, `link_global_tree`, `has_other_link_ref`, `prune_superseded`, `ensure_omp` |
| verify, self | `check_addons`, `run_verify`, `path_hint`, `path_reminder`, `link_self`, `tool_label`, `cmd_install_self`, `cmd_uninstall_self`, `cache_get`, `cache_put`, `record_release`, `refresh_release_cache`, `update_checks_on`, `check_self_update`, `cmd_update_self` |
| verbs, dispatch | `resolve_target`, `device_is_current`, `cmd_install`, `show_path`, `cmd_status`, `cmd_doctor`, `main` |

- Single writer: `resolve_env` is the only reader of `HOME`/`XDG_*`/`BUN_INSTALL`/`PATH` and the only writer of
  `BIN_HOME`, `CACHE_HOME`, `TMP_HOME`, `BUN_DEFAULT`, `BUN_ROOTS`, `BUN_HOME`, `BUN_BIN`, `OMP_BIN`;
  `scratch_open` owns `SCRATCH`. One exception: `download_bun` sets `BUN_BIN` for the root it just provisioned.
  Everything else takes arguments or reads those variables and prints results instead of setting caller state. Call
  `resolve_env` again after a step that changes bun's tree.
- Scratch: one `$CACHE_HOME/run.<pid>` per `install`/`verify` run, opened by `scratch_open` and removed by an `EXIT`
  trap (`scratch_reap`, which also removes `$CACHE_HOME` when empty). Opening reclaims dirs whose pid is gone
  (`kill -0`) and leaves live runs alone. No other verb opens one; downloads live only inside it.
- Output: results on **stdout** (`result` → `omp-termux: …`); progress and diagnostics on **stderr** (`msg` → `==> …`,
  `warn` → `warning: …`, `die`/`err`/`print_error` → `omp-termux: error: …`, plus `hint: …` when passed). Color
  only on a tty; `OMP_TERMUX_VERBOSE=1` uncaps leftover rows with their export counts, adds the install-time load
  mode, and prints absolute paths in `status`.
- One implementation per mechanism: `http URL OUT MAX` is the only `curl` call site (prints
  `<status> <effective URL>`; `000`/empty = network failure; `MAX` 1800 for the addon and bun zip, 20 for lookups
  and self-update). `stage_into` is the only copy-and-rename for an installed addon (`DST.part.$$`, then `mv`); the
  tool's own copy and `update-self` stage and rename their own paths the same way. No `api.github.com`: the API
  quota, lookups follow `releases/latest`. Self-update compares content hashes (fetch, `bash -n`, sha256, `mv`),
  with no conditional GET and no validator cache.
- Install order is the contract: the addon is fetched and verified before omp is touched, and bun reaches the
  installed omp's `engines.bun` floor before the addon lands. Already current prints `nothing to do (omp <version>)`
  and downloads nothing; `device_is_current` also proves `omp` starts. The steps are in `docs/dev/tool.md`.

## Key Directories

| Path | Purpose |
|---|---|
| `bin/omp-termux` | The device tool: environment, install/verify/status/doctor, self-update. |
| `dev/omp-termux-dev` | The build script: cross-compile, drive a target device over ssh. |
| `install.sh` | Bootstrap: fetch raw `bin/omp-termux`, `bash -n`, run `install latest` (or the given/`$OMP_TERMUX_VERSION`). |
| `patches/` | Vendored upstream PR #6350 patch with provenance header; read only by the build script. |
| `.github/workflows/build.yml` | The only CI: build on tag/dispatch, publish release `omp-<version>`. |
| `README.md`, `README.zh-CN.md`; `docs/user/font.md`, `.zh-CN.md` | User side: install, verbs, caveats; Nerd Font notes. |
| `docs/dev/build.md`, `docs/dev/tool.md` | Build and device-tool design docs; `.zh-CN.md` twins beside each. |
| `tests/verify.sh` | The local gate: static checks plus the fake-device matrices. |
| `work/`, `out/` | Gitignored: clone + cargo target + opus prefix + napi-cli; built artifacts. |

## Development Commands

```sh
sh tests/verify.sh                          # the local gate: syntax + shellcheck, then the fake-device matrices
./bin/omp-termux help                       # device verbs = header lines 4-10 (usage() prints them)
./dev/omp-termux-dev help                   # build verbs = header lines 4-10
./dev/omp-termux-dev doctor                 # build toolchain report (NDK, rustup, cmake, ninja)
./dev/omp-termux-dev build 18.18.3          # cross-compile only (rustup + NDK + bun + cmake + ninja)
./dev/omp-termux-dev device user@host       # save the target device (port from ssh -G, else 8022)
./dev/omp-termux-dev install 18.18.3        # build when needed, upload, install and verify on the device
```

- One commit per meaningful change, conventional `type: subject` with a terse body; released commits and tags are
  never rewritten. `work/src` is a throwaway clone `fetch_source` wipes or hard-resets: never hand-edit it.

## Code Conventions & Common Patterns

- `set -Eeuo pipefail` plus an `ERR` trap that prints the failing line; guard tolerated failures (`|| true`).
  Function shape: `name() {` on its own line, `local` first, `# $1 = …` on the definition line. Tests use `[ … ]`,
  never `[[ … ]]`; output is `printf`.
- The header block **is** the help text: each script prints its own lines 4-10. Adding a verb means editing that
  range.
- The scripts share by sourcing, never by copying; the dispatch is an `if`, not `[ … ] &&`, because sourcing must
  not fail under `set -e`. Shared names: `ADDON`, `UPSTREAM_REPO`, `REPO`, `PROG`, `msg`, `result`, `warn`, `err`,
  `die`, `have`, `version_*`, `latest_version`, `artifact_version`, `file_sha`, `same_path`, `reject_option`,
  `require_file_arg`, `resolve_env`, `installed_state`. Nothing else crosses the boundary; the build script's
  upload directory is `REMOTE_SCRATCH`, never the tool's `SCRATCH`.
- Idempotency is a requirement: `cmd_install_self` skips copying onto itself and stages+renames, `link_self` leaves a
  real directory alone, `link_global_tree` only refreshes symlinks, `apply_patch` greps its marker, a current
  install fetches nothing. No shims or aliases: each mechanism has one implementation.
- Environment inputs are `OMP_TERMUX_*`; the lists are in `docs/dev/tool.md` and the scripts' headers. Defaults must
  cover the device: it never needs an export to work.
- `reject_option` rejects a leading `-` wherever an argument is optional or absent, so `status --json` errors instead
  of running silently; unknown verbs warn, print usage and exit 1.
- `check_self_update` runs before every verb except `help` and `update-self`, only from the installed copy and without
  `OMP_TERMUX_NO_UPDATE_CHECK`. It fetches the script, compares sha256, caches `self`/`checked_at`/`hash`/`version`
  for `OMP_TERMUX_UPDATE_TTL` seconds (default 86400) under `$PREFIX/cache/self-update`, and prints one `msg` line
  when they differ — never stdout, never an exit code. `refresh_release_cache` keeps `release`/`release_checked_at`
  (the `newest` row); an install that resolves a release records it, so `status` is not stale after one.
- Comments carry only non-obvious external constraints (loader release check, bun cache/global layout,
  `audiopus_sys`, the addon stamp), one line where possible; rationale lives in `docs/dev/tool.md` and
  `docs/dev/build.md`, and never restates code.
- Docs are a bilingual pair-set with **English canonical**: commands, flags, paths, env vars, file names, error
  strings and fenced blocks stay byte-identical across pair members. Keep the switcher on line 3, break prose after
  punctuation, no personal data. `README.md` is user-side and says nothing about the build; `docs/dev/*` is for
  maintainers. Never teach a hand copy.

## Important Files

- Constants: `TERMUX_PREFIX` is captured **before** `PREFIX` is reused for the tool's own copy (reordering breaks
  install paths); `ADDON` is loader-visible; `PROG` names the script; `TOOL_VERSION` is a label only, since
  comparisons read the content hash.
- `resolve_env` derives `BIN_HOME` (`$TERMUX_PREFIX/bin` → `XDG_BIN_HOME` → `~/.local/bin`), `CACHE_HOME`
  (`OMP_TERMUX_CACHE_HOME` → `$XDG_CACHE_HOME/omp-termux` → `~/.cache/omp-termux`; relative, `/` or `$HOME` refused),
  `TMP_HOME`, `BUN_DEFAULT` (`BUN_INSTALL` → `XDG_CACHE_HOME/.bun` → `~/.bun`), `BUN_ROOTS` (existing, bun's order,
  `~/.cache/.bun` last), `BUN_HOME`, `BUN_BIN`, `OMP_BIN`. `use_root` pins the shell; relative values are ignored.
- `installed_state` prints one `|`-separated record, `version|addon|dir|cli` (`dir` = what `$BUN_HOME`'s tree
  resolves; `addon` = `native/$ADDON`; `cli` = the omp beside it). Verbs parse it with `IFS='|' read -r …`.
- `artifact_version` reads `PI_NATIVES_VERSION_STAMP:<version>` and falls back to `__piNativesV<major>_<minor>_<patch>`; an
  unstamped addon is refused by the loader. Only the workstation path needs `stamp_artifact`.
- `check_addons FULL`: probes the loaded copy and every leftover, but `FULL=1` (verify) prints at most two leftover
  rows unless verbose (a failing leftover always prints); `FULL=0` (install) is silent on success and dies on the
  loaded copy. `run_verify` adds `omp … starts` and ends with `result "verify ok"`.
- `cmd_status` prints `tool`, `omp`, one `addon` row per `natives_dirs` entry (size, `loaded`/`leftover`), `newest`
  when cached, and `paths`; `$HOME` collapses to `~`. The build script parses the `omp` row: keep the format.
- `fetch_release` downloads into scratch, classifies HTTP (404/4xx/5xx/000 change nothing), and rejects an addon
  whose stamp is not the requested version. `install_addon` takes the target from that stamp. `prune_superseded`
  keeps copies a link still reaches, and its `find` omits `-L`.
- Build script anchors: `PROJ`, `WORK`/`OUT`/`SRC`/`NAPI_CLI_DIR`/`OPUS_PREFIX`/`CARGO_TARGET`, `API=24`, `UPSTREAM`,
  `PR=6350`, `PR_PATCH_URL`, `NDK`, `PATCH`, `REMOTE_SCRATCH`, `STAGED`, `CFG`.
- Cross-file couplings: asset name (`build.yml` ⇄ `$ADDON` ⇄ `fetch_release` ⇄ `finalize_artifact`), tag
  `omp-<version>`, URL bases, CI cache paths mirroring the build dirs, `PR=6350` matching the patch header, and the
  `TOOL_VERSION=` line `install.sh` parses.

## Runtime/Tooling Preferences

- Device: bash + bun (`curl`, `unzip` for the bun fallback, `pkg` when Termux provides bun); the floor is the
  installed omp's `engines.bun`. No rust, clang or NDK unless building there.
- Workstation: `rustup`, `bun` ≥ 1.3.14, Android NDK, `cmake`, `ninja`, `git`, `curl`, `unzip`, `file`, binutils.
  The NDK search order is in `docs/dev/build.md`.
- Rust channel and `@napi-rs/cli` version come from the upstream clone; CI pins `bun-version: 1` only.
  `shellcheck -S warning` is part of the local gate; a required construct may carry one `# shellcheck disable=SCxxxx`
  with the reason, never a file-level disable. No package manager, lockfile, JS/TS sources, or formatter here.

## Privacy

No telemetry, no identifiers, nothing sent beyond the request itself. The only endpoints are:

- `raw.githubusercontent.com/<repo>/main/...` — bootstrap in `install.sh` and the self-update fetch.
- `github.com/<repo>/releases/latest` — the 302 the release lookups follow.
- `github.com/<upstream>/releases/latest` — the newest upstream omp release (build target).
- `github.com/<repo>/releases/download/omp-<ver>/pi_natives.android-arm64.node` — the addon.
- `github.com/oven-sh/bun/releases/latest/download/bun-linux-aarch64-android.zip` — the bun fallback.
- `github.com/<upstream>.git` — the build script's clone.
- `patch-diff.githubusercontent.com/raw/<upstream>/pull/6350.diff` — the patch fallback.
- ssh/scp to `OMP_TERMUX_HOST` — the device verbs.

`OMP_TERMUX_NO_UPDATE_CHECK` disables the only periodic request. `tests/verify.sh` asserts this allowlist over every
URL literal; a new endpoint means updating both the list and the gate.

## Testing & QA

- `sh tests/verify.sh` is the local gate: `bash -n` on both scripts, `sh -n install.sh`, `shellcheck -S warning
  bin/omp-termux dev/omp-termux-dev install.sh tests/verify.sh`, argument-hygiene checks, then the fake matrices.
- Device matrix (stubbed `curl`/`bun`, isolated `HOME`/`PATH`/`TMPDIR`): install/verify/status/doctor contracts,
  results on stdout and progress on stderr, `nothing to do` when current, `omp <ver> ready (…)`, a missing release
  changing nothing, and the self-update cache keys.
- Build matrix (stubbed `ssh`/`scp`, fake device HOME): the tool stages at `~/.cache/omp-termux/build`, the artifact
  is uploaded there, the staged tool installs and verifies it, no scratch survives; `status`/`verify` go over the
  wire.
- Environment matrix: no XDG, XDG set and exported empty, `BUN_INSTALL`, relative `XDG_CACHE_HOME`/`CACHE_HOME`;
  bun's root wins over the XDG-era leftover, and a decoy tree in the current directory is never written.
- Invariants: two concurrent `verify` runs succeed and leave nothing; a `run.<pid>` whose pid is gone is reclaimed,
  a live one kept; a failed install leaves the root absent; `stage_into` leaves no `.part`; egress holds. Device
  sections need `out/pi_natives.android-arm64.node` and skip without it; one fixture records its version the
  pre-stamp way, so both `artifact_version` identities are exercised.
- CI has **no verification job**: it only builds and publishes, with `verify_artifact` inline as the last automated
  check; `sh tests/verify.sh` is the local bar. Extend it whenever a bug escapes, asserting behavior over internals.
- Not verifiable without hardware: bun's global layout on Android, the NDK cross-build, the real ssh transport, and
  anything touching `pkg`/`termux-*`. Say so when reporting.
