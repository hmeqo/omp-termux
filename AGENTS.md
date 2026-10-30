# Repository Guidelines

## Project Overview

`omp-termux` makes `omp` (the oh-my-pi coding agent) run on Android aarch64 / Termux. Upstream publishes no
Android build of its native addon `@oh-my-pi/pi-natives`, so `omp` aborts with
`Unsupported platform: android-arm64`. This repo supplies that addon — cross-compiled with the Android NDK
carrying upstream PR #6350, or downloaded prebuilt from this repo's GitHub releases — and installs it into the
`@oh-my-pi/pi-natives` package the user already has. `omp` itself is never rebuilt.

## Architecture & Data Flow

Two bash scripts do the work: one for the device, one for building the addon.

- `bin/omp-termux` — the device tool, and it has no mode: by design it is the device side, so it asks nothing
  about the machine it starts on and reports whatever pi-natives it finds. The helpers sit under
  `# --- section ---` banners (reporting, environment resolution, installed-addon inspection, the tool's
  own install and update check, the device install, the release lookups, doctor, dispatch); all verbs are one
  `case` in `main`.
- `dev/omp-termux-dev` — the build half: what the NDK, rustup, cmake, ninja and the vendored patch need, and
  nothing the device runs. It sources `bin/omp-termux` for `$ADDON`, `$UPSTREAM_REPO`, `$SELF` and the shared
  helpers, so those exist once, and asks where it runs itself (`TERMUX_VERSION` set or
  `/data/data/com.termux/files/usr` present ⇒ device; `OMP_TERMUX_MODE` overrides). Verbs: `build`, `install`,
  `status`, `verify`, `device`, `doctor`.
- Device access (workstation): `device` saves a target (`OMP_TERMUX_HOST`/`OMP_TERMUX_PORT` win over
  `~/.config/omp-termux/config`, the port also via `ssh -G`), `install` resolves what to install, builds when
  `out/` does not already hold it, uploads the artifact and `$SELF` (the tool) into its own scratch on the
  device (`OMP_TERMUX_CACHE_HOME`, else `~/.cache/omp-termux`, both relative to the device's `$HOME`), runs the
  tool there, and verifies on the device; `status`/`verify` are the same round trip without changing anything.
  These verbs refuse in device mode.
- Build path (workstation or CI): `workstation_build` → `fetch_source` (clone `UPSTREAM` at tag `v<version>` into
  `work/src`) → `ensure_rust_target` → `apply_patch` (vendored `patches/*.patch`, else the PR diff from the
  network) → `install_build_deps` → `prepare_opus` → `cross_build` (napi-rs CLI, `--profile ci`,
  `aarch64-linux-android`, into the `out/.build` staging dir) → `finalize_artifact` (move this run's link from
  there to `$ADDON`, then `stamp_artifact`) → `verify_artifact "$version"`.
- Build path (device, hours): `device_build` builds through upstream's `packages/natives/scripts/build-bindings.ts`
  and leaves the addon in `work/`, which is what a device `install` reads.
- Install path (device): `device_install` → `link_global_tree` (Termux bun-layout repair) → `fetch_release` (or a
  local `.node`) → `install_addon` (`cp` into every matching `@oh-my-pi/pi-natives/native/`, skipping version
  mismatches) → `run_verify` (loads `native/index.js` through bun and checks the expected export set) →
  `cmd_install_self` (the tool puts its own copy at `$PREFIX/bin/omp-termux` and links it into `$BIN_HOME`, which
  is what makes the next run able to self-update; it is a step of `install`, not a verb).
- CI (`.github/workflows/build.yml`) runs exactly `./dev/omp-termux-dev build "$VERSION"` and publishes release
  `omp-<version>` carrying `out/pi_natives.android-arm64.node`; the adapter the package loads is the package's
  own, because the addon only lands in the package whose version it reports.
- `install`, `status`, `verify` and `doctor` act on the pi-natives of the machine that runs them, so they are
  device verbs; `help` and the self-management verbs (`update-self`, `uninstall-self`) work anywhere. Building
  lives in the other half. The tool's own scratch is `$CACHE_HOME` (`OMP_TERMUX_CACHE_HOME`, else
  `$XDG_CACHE_HOME/omp-termux`, else `~/.cache/omp-termux`) and the build half uploads into its own
  `$SCRATCH`: with nothing set both are `~/.cache/omp-termux`, which is what the majority of devices (no XDG
  anywhere) use, and each side removes its own afterwards. `work/` and `out/` are gitignored local state.

## Key Directories

| Path | Purpose |
|---|---|
| `bin/omp-termux` | The device tool (bash, hard tabs, ~700 lines). |
| `dev/omp-termux-dev` | The build half (bash, hard tabs, ~600 lines); sources `bin/omp-termux` and drives a target device over ssh. |
| `install.sh` | Device bootstrap for ordinary users: fetch raw `bin/omp-termux`, `bash -n` it, run device `install`. |
|`patches/`|Vendored upstream PR #6350 patch: provenance header, then 11 diffs over 11 files against v18.14.0. Read only by the build half.|
| `.github/workflows/build.yml` | The only CI: cross-compile and publish one release per omp version. |
| `docs/` | `README.zh-CN.md` (translation of `README.md`), `build.md` / `build.zh-CN.md` (the build half), `font.md` / `font.zh-CN.md` (Nerd Font notes). |
| `work/`, `out/` | Gitignored: upstream clone + cargo target + opus prefix + napi-cli; built artifacts. |

## Development Commands

```sh
bash -n bin/omp-termux && bash -n dev/omp-termux-dev && sh -n install.sh   # syntax gates
sh tests/verify.sh                              # the local gate: static checks + the device paths, fake device
./bin/omp-termux help                           # device verbs = header lines 4-10, printed by usage()
./dev/omp-termux-dev help                       # build verbs = header lines 4-6
./dev/omp-termux-dev doctor                     # build toolchain report (NDK, rustup, cmake, ninja)
./dev/omp-termux-dev build 18.3.4               # cross-compile only (needs rustup + NDK + bun + cmake + ninja)
./dev/omp-termux-dev device user@host           # save the target device for the verbs below
./dev/omp-termux-dev install 18.3.4             # build when needed, upload, install and verify on the device
./dev/omp-termux-dev status                     # what the target device runs (over ssh)
OMP_TERMUX_MODE=device ./dev/omp-termux-dev build   # native build on the phone: hours, takes termux-wake-lock
```

- CI is reproduced locally by `./dev/omp-termux-dev build "$VERSION"` — nothing else runs there.
- One commit per meaningful change, conventional `type: subject` with a terse body; the released commit and
  its tag are never rewritten.
- `work/src` is a throwaway clone that `fetch_source` wipes or hard-resets: never hand-edit it.

## Code Conventions & Common Patterns

- `set -Eeuo pipefail` plus an `ERR` trap that prints `script:line:command`. With `pipefail`, any tolerated
  failure must be guarded (`|| true`, `|| warn …`).
- Reporting goes through `msg` (stdout, `==>`), `warn` (stderr, non-fatal), `die` (stderr, `exit 1`) and `hint`
  (stderr, the `==>` look, for lines that must not appear on a verb's stdout). Tests use `[ … ]`, never
  `[[ … ]]`; output is `printf`.
- Function shape: `name() {` on its own line, `local` first, `# $1 = …` doc-comment on the definition line,
  sections separated by `# --- name ---` banners padded to ~100 columns.
- Comments are reserved for non-obvious external constraints — the loader's release check, bun's
  cache/global layout, `audiopus_sys` having no `rerun-if-env-changed`, opus' CMake predating CMake 4, and the
  addon's post-link stamp. Never restate code.
- The header block **is** the help text, per file: the tool prints lines 4-10 (`usage()` is
  `sed -n '4,10p' "$SELF"`), the build half lines 4-6 off its own path. Adding a verb means editing that range.
- The halves share by sourcing, never by copying: `dev/omp-termux-dev` sources `bin/omp-termux`, whose trailing
  dispatch is guarded by `if [ "${BASH_SOURCE[0]}" = "$0" ]` — an `if`, not `[ … ] &&`, because sourcing must
  not report failure under `set -e`. A name or helper both halves need belongs in the tool.
- Idempotency is a requirement, not a nicety: `cmd_install_self` skips copying onto itself, `link_global_tree`
  only refreshes symlinks and never clobbers real directories, `apply_patch` greps for its marker, `update-self`
  runs `bash -n` + sha256 + `mv` before replacing.
- Environment inputs are `OMP_TERMUX_*`: `REPO`, `RELEASE_BASE`, `RAW_BASE`, `CACHE_HOME` (the scratch
  directory), `VERSION`, `NO_UPDATE_CHECK`, `UPDATE_TTL` for the tool, `NDK`, `MODE` and `HOST`/`PORT` (the
  ssh target) for the build half; the device must never need an export to work — defaults cover it.
- Argument hygiene: `reject_option` rejects a leading `-` — for `install` (the tool) and `build` (the build half),
  where an argument is expected at all, and for every verb that takes none, so `status --json` is an error and
  not a silent `status`. It names the running script through `$PROG`.
- `check_self_update` runs before every verb except `help` and `update-self`, and only when the running file is
  the installed copy. It compares the content hash of `main` (conditional GET, `ETag`) with its own, caches the
  result for `OMP_TERMUX_UPDATE_TTL` seconds under `$PREFIX/cache/self-update` so most verbs never talk to the
  network, and prints one line to stderr when they differ. It never writes to stdout and never changes an exit
  code; the cache is also where `status` gets its `newest here` line, and it is keyed to the copy that fetched
  it, so a tool replaced by other means re-checks instead of reporting a difference that does not exist. The
  version lookup resolves `<repo>/releases/latest`'s 302 instead of the GitHub API: the API's 60 requests per
  hour are per IP and a phone behind carrier NAT shares that with strangers.
- Docs (`README.md`, `docs/*.md`) are a bilingual pair-set with **English canonical**: prose is translated, while
  every command, flag, path, env var, file name, error string and fenced code block stays byte-identical between
  the two files. Content may differ only where the audience differs (today: the `-CN` font variant exists only in
  the Chinese font doc). Keep the language switcher on line 3, prose lines broken after punctuation (`。,:;、`)
  and never left ending on a CJK function word, and no personal paths, usernames or e-mail addresses anywhere.
- Docs describe what a user does and sees: `README.md` is the user side (the bootstrap, the device verbs and the
  caveats), and `docs/build.md` is the maintainer side (what the build half needs, the build itself, and putting
  the result on a device). The tool provisions bun and omp itself and the build half puts its build on a device
  over ssh, so no doc teaches a hand copy or a hand-managed bun/omp. Do not document build mechanics, CI cadence,
  internal cache paths or loader internals there; that knowledge belongs in the code comment next to the
  mechanism.

## Important Files

- `bin/omp-termux` globals (near the top): `TERMUX_PREFIX` is captured **before** `PREFIX` is reused as the
  tool's own prefix (reordering breaks device install paths);
  `ADDON=pi_natives.android-arm64.node` is the loader-visible name used by install/fetch/verify (and by the
  build half); `PROG` names the script in hints, `UPSTREAM_REPO` is the upstream owner/repo as a literal (the git
  URL lives in the build half), `REPO` this repository.
- `dev/omp-termux-dev` globals: `PROJ` (the checkout it runs from), `WORK`/`OUT`/`SRC`/`NAPI_CLI_DIR`/
  `OPUS_PREFIX`/`CARGO_TARGET`, `API=24`, `UPSTREAM`, `PR=6350`, `PR_PATCH_URL`, `NDK`, `PATCH`.
- `bin/omp-termux`'s own identity and update state: `TOOL_VERSION` (a human label only — every
  comparison reads the content hash, so nothing pins its value), `SELF_URL` (raw `main`, shared with `cmd_update_self`), `SELF_CACHE`
  (`$PREFIX/cache/self-update`, removed by `uninstall-self` together with the prefix) and `SELF_TTL`.
- Environment resolution happens once, in `resolve_env`: it sets the variables every verb reads — `BUN_HOME`
  (the root in use), `BUN_ROOTS`, `BUN_DEFAULT` (bun's rule for a *new* root), `BUN_BIN`, `OMP_BIN`, `BIN_HOME`,
  `CACHE_HOME` and `TMP_HOME` — from the rules above it (`absolute_dir`, `bun_default_root`,
  `existing_bun_roots`, `bun_root_in_use`, `bin_home_dir`, `cache_home_dir`, `bun_binary_path`,
  `omp_binary_path`, `tmp_dir`). `use_root` pins the shell at `$BUN_HOME`; installing bun or omp calls
  `resolve_env` again. Nothing below re-derives any of it. `REMOTE_ROOT_PROBE` is the POSIX twin of the root
  rule, which the build half has the device evaluate before it can run anything there.
- Key functions, tool: `usage`, `install_addon`, `stray_scope_deps`, `link_global_tree`, `fetch_release`, `device_install`,
  `run_verify`, `installed_state`/`newest_natives_dir` (what the device actually loads: `CUR_DIR` and
  `CUR_VERSION`/`CUR_ADDON` for that copy, `CUR_CLI_VERSION` for the omp it runs), `check_self_update`,
  `cache_get`/`cache_put`, `print_status`, `cmd_install_self`, `cmd_update_self`,
  `cmd_uninstall_self`, `path_hint`/`path_reminder`, plus the dispatch in `main` (line numbers drift; search by name).
- Key functions, build half: `detect_ndk`/`ndk_ok`, `vendored_patch`, `fetch_source`, `apply_patch`,
  `install_build_deps`, `device_build`, `ensure_rust_target`, `prepare_opus`, `cross_build`, `stamp_artifact`,
  `finalize_artifact`, `verify_artifact`, `workstation_build`, `ensure_artifact`, `build_doctor`, and the device
  access: `device_host`/`device_port`, `device_ssh`/`device_scp`, `remote_bun_root`/`remote_bun_env`,
  `ensure_device_bun`/`ensure_device_version`, `device_run`/`device_upload`, `device_installed_version`,
  `resolve_target`, `install_on_device`, `workstation_install`, `cmd_device`.
- Contracts worth re-reading before an edit: `fetch_release` removes the scratch dir before `die` so a missing
  release changes nothing, and it only accepts an addon that reports the requested version;
  the device access uploads `$SELF` — the tool being developed — and lets it install on the far side, so a
  change to the tool is what the next `omp-termux-dev install` exercises; `workstation_install` compares the
  caller's artifact with `readlink -f` before copying, because `cp` refuses the same file under another
  spelling; `device_install` also accepts a local `.node` — the build half uploads one and has the device tool
  install it, which is why that form stays in the code and out of the docs — and it fetches the addon **before**
  upgrading omp, resolves `latest` from this repository's newest
  published release, skips everything (download included) when that version is already installed and loads, and
  fails only when the omp the device runs is newer than anything published here — that version comes from the
  CLI package, never from the pi-natives the tree happens to hold. The CLI pins its whole `@oh-my-pi` scope
  exactly, but bun keeps an entry an older install left in the global manifest and resolves it to the newest
  version its range allows, so the tool drops those entries on the paths where the verb acts (the skip
  included, never on the way to a refusal) and lets the CLI's own pins decide the tree. A tree that drifted
  with no entry to blame is forced back by naming the addon's package on the install line, whose entry is then
  taken out again;
  `run_verify` hangs its verdict on the copy the device loads while reporting the others;
  `install_addon` takes the target
  version from the artifact's own stamp (the same release the loader compares), so nothing reads a source tree
  any more;
  `verify_artifact` hard-fails on
  non-`ARM aarch64`, a missing NDK note, any `GLIBC_` need, or `libc.so.6`/`ld-linux` NEEDED entries.
- Release identity of an addon: a 64-byte slot the build stamps after linking (`PI_NATIVES_VERSION_STAMP:<version>`,
  reported at runtime by `__piNativesBuildVersion()`). Releases before that slot exported a per-release napi
  name (`__piNativesV18_3_2`) instead, and `artifact_version` reads both. Only the workstation path needs
  `stamp_artifact`: upstream's `build-bindings.ts` stamps on its own, which the device build uses. An unstamped
  addon reports no release and the loader refuses to load it.
- Cross-file couplings: asset names (`build.yml` ⇄ `$ADDON` ⇄ `fetch_release` in the tool ⇄ `finalize_artifact`
  in the build half), tag naming `omp-<version>` (workflow trigger, skip guard, download URL), URL bases
  (`REPO`/raw base in `install.sh` and the tool), CI cache paths mirroring the build half's
  `WORK`/`CARGO_TARGET`/`NAPI_CLI_DIR`/`OPUS_PREFIX`/`SRC`, `PR=6350` in the build half matching the patch
  header, `LICENSE` footer and README credits (which is why `vendored_patch` only accepts a patch file whose
  header names the current `$PR`), the `TOOL_VERSION=` line that both the tool and `install.sh` parse to print a
  version (the tool labels itself with it, the bootstrap only reports it), and the sourced half itself:
  `$ADDON`, `$UPSTREAM_REPO`, `$SELF` and the reporting/version helpers are defined once, in the tool.

## Runtime/Tooling Preferences

- Device: bash + `bun` only (`curl`, `unzip` for the bun fallback). No rust, clang or NDK unless building there.
- Workstation: `rustup`, `bun` ≥ 1.3.14, an Android NDK, `cmake`, `ninja`, `git`, `curl`, `unzip`. NDK
  lookup order: `OMP_TERMUX_NDK` → `ANDROID_NDK_ROOT` → `ANDROID_NDK_HOME` → `ANDROID_NDK_LATEST_HOME` →
  `$ANDROID_HOME/ndk/*` (newest) → `/opt/android-ndk`; the host dir `toolchains/llvm/prebuilt/linux-x86_64` is
  hard-coded.
- bun's install root is resolved in one place (`resolve_env`, its rules above it) and must never be hard-coded:
  it is `BUN_INSTALL`, else `$XDG_CACHE_HOME/.bun` when that variable is set, else `~/.bun`. Everything that
  touches the global tree, this tool's own directories or a bun binary goes through `resolve_env` and the
  variables it sets, and every root that exists is visited in bun's own rule order: the XDG-era leftover
  `$HOME/.cache/.bun`, which bun reaches only through `XDG_CACHE_HOME`, comes last, so an unset
  `XDG_CACHE_HOME` leaves `~/.bun` in use even when that leftover carries omp too. A relative `BUN_INSTALL`,
  `XDG_CACHE_HOME`, `XDG_BIN_HOME` or `OMP_TERMUX_CACHE_HOME` is not a path any tool could use (bun's own
  global install dies with `EACCES`) and is ignored, in the tool and in the device probes alike.
- Rust channel and `@napi-rs/cli` version come from the upstream clone (`rust-toolchain.toml`,
  `package.json`) — never pin them here. CI pins `bun-version: 1` only.
- No package manager, lockfile, linter or formatter in this repo; no JS/TS sources of its own.

## Testing & QA

- `sh tests/verify.sh` is the local gate: syntax checks, then the device paths against a fake device (stubbed
  `bun`/`curl`, isolated `HOME`/`TMPDIR`/`XDG_CONFIG_HOME`, `TERMUX_VERSION=0.118`), and a workstation section
  that asserts `install`/`status`/`verify`/`doctor` refuse there, that `build` is no longer a tool verb, and that
  the build half answers `help` and rejects an unknown verb. The device sections need
  `out/pi_natives.android-arm64.node` and are skipped without it; one release fixture records its version the
  pre-stamp way, so both identities the tool reads are exercised. It never touches a real device or the network,
  and refuses to run if its `/tmp` paths are not what it expects. Its stubbed bun copies the two behaviours the
  tool leans on: a device that has bun's global layout gets it rewritten at the version asked for, and a tree
  holding no addon for the platform cannot load — so a device carrying a stale copy from another release is
  exercised (the fake device gets a global tree only where a case asks for one).
- Extend that script whenever a bug escapes it: the harness is what caught the truncated `fetch_release`, the
  prune that deleted a link target and the `ln -sfn`-into-a-directory case, but the "no-argument install picked
  the oldest version" bug only showed up on a real device.
- CI has no test job: the only automated gates there are `dev/omp-termux-dev build` and the in-script
  `verify_artifact` / `run_verify`.
- Contracts to assert after touching install/update code: unknown verbs and option-looking arguments exit 1;
  `install latest` on a device already at the published version exits 0, prints `nothing to do` and fetches
  nothing, while one that needs a download but has no release exits non-zero, calls no `bun install -g`, and
  prints `nothing was changed`; a device ahead of everything published here exits non-zero and leaves the addon
  untouched; a device whose tree holds a *newer* pi-natives than the omp it runs is not ahead — it is repaired:
  the scope entries kept in the manifest are dropped (an install with nothing else to do drops them too,
  while a refused or failed one leaves them alone), bun is asked for the CLI at the published version, the
  addon's package is named when the tree is off target and that pin is taken back out, the addon lands in the
  tree omp loads, a leftover copy of another release is reported without failing the run, and the next install
  has nothing to do;
  an addon that reports another version is rejected; repeated installs stay idempotent;
  the device end state is the addon plus `~/.local/opt/omp-termux` plus one symlink (`$BIN_HOME`: `$PREFIX/bin`
  on Termux, else `$XDG_BIN_HOME` or `~/.local/bin`) and nothing else; the PATH hints are asserted too: one per
  missing directory, bun's bin dir only once something to run sits in it, and none when the shell reaches both; `update-self` refuses a script that
  fails `bash -n` and
  keeps the old copy, and drops the self-update cache so the next verb re-checks.
- The self-update check is asserted through a stubbed `curl` that logs every call: one stderr line when `main`
  differs and none when it matches, no request at all while the cache is fresh or when
  `OMP_TERMUX_NO_UPDATE_CHECK` is set, and its scratch files never survive into `$TMPDIR`.
- The device access is asserted with stubbed `ssh`/`scp` that log every call and run the command line against a
  fake device HOME: the artifact and the tool are uploaded, the tool installs them there, the
  scratch dir is gone afterwards, and `status` asks the device rather than acting locally.
- The resolved environment is asserted on every layout (no XDG, XDG set, XDG exported empty, `BUN_INSTALL`,
  and relative `XDG_CACHE_HOME`/`OMP_TERMUX_CACHE_HOME` values): the root probe must print what the tool's
  `$BUN_HOME` holds, its `$CACHE_HOME` must follow the XDG cache dir (and ignore a relative value), bun's own
  root must win over the XDG-era leftover, and an install must not take the addon into a decoy the current
  directory happens to hold. The build half's own `$SCRATCH` is asserted through the stubbed `ssh`/`scp` log:
  `~/.cache/omp-termux` by default, `OMP_TERMUX_CACHE_HOME` when the caller sets it.
- Not verifiable without real hardware: bun's global layout behaviour on Android (the `link_global_tree` repair),
  the NDK cross-build, the real ssh transport, and anything touching `pkg`/`termux-*`.
- Doc statements are the user-visible contract — `README.md` must stay true: the install prose and the command
  table carry the addon-must-match and tool-on-PATH facts plus `uninstall-self` leaving omp alone, the
  limitations keep arm64-v8a only and API 24 / Android 7+, and the caveats keep the Termux viewport behaviour.
