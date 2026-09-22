# Repository Guidelines

## Project Overview

`omp-termux` makes `omp` (the oh-my-pi coding agent) run on Android aarch64 / Termux. Upstream publishes no
Android build of its native addon `@oh-my-pi/pi-natives`, so `omp` aborts with
`Unsupported platform: android-arm64`. This repo supplies that addon — cross-compiled with the Android NDK
carrying upstream PR #6350, or downloaded prebuilt from this repo's GitHub releases — and installs it into the
`@oh-my-pi/pi-natives` package the user already has. `omp` itself is never rebuilt.

## Architecture & Data Flow

One bash script is the product; every other file supports it.

- `bin/omp-termux` — the whole tool. `MODE=workstation|device` is decided once at startup (`TERMUX_VERSION` set
  or `/data/data/com.termux/files/usr` present ⇒ device; `OMP_TERMUX_MODE` overrides). ~70 helper functions sit
  under six `# --- section ---` banners (installed-addon inspection, install, device build, workstation build,
  device access, dispatch); all verbs are one `case` at the end of the file.
- Build path (workstation or CI): `workstation_build` → `fetch_source` (clone `UPSTREAM` at tag `v<version>` into
  `work/src`) → `ensure_rust_target` → `apply_patch` (vendored `patches/*.patch`, else the PR diff from the
  network) → `install_build_deps` → `prepare_opus` → `cross_build` (napi-rs CLI, `--profile ci`,
  `aarch64-linux-android`) → `finalize_artifact` (renames the bare `pi_natives*.node` to `$ADDON`, also copies
  `desktop-adapter.js` and the script itself into `out/`) → `verify_artifact`.
- Install path (device): `device_install` → `link_global_tree` (Termux bun-layout repair) → `fetch_release` (or a
  local `.node`) → `install_addon` (`cp` into every matching `@oh-my-pi/pi-natives/native/`, skipping version
  mismatches) → `run_verify` (loads `native/index.js` through bun and checks the expected export set) →
  `cmd_install_self`.
- Install path (workstation): `resolve_target` (sets the globals `TARGET_VERSION`/`TARGET_FILE`) →
  `ensure_device_version` → `ensure_artifact` (freshness read from the sentinel inside `out/$ADDON`, not from a
  manifest) → `install_on_device` (upload script + artifact into `~/$SCRATCH`, run `install <file>`, then
  `verify` over ssh).
- CI (`.github/workflows/build.yml`) runs exactly `./bin/omp-termux build "$VERSION"` and publishes release
  `omp-<version>` with two assets: `out/pi_natives.android-arm64.node` and `out/desktop-adapter.js`.
- Device scratch `$HOME/.cache/omp-termux` is created and removed inside the same ssh session; `work/` and
  `out/` are gitignored local state.

## Key Directories

| Path | Purpose |
|---|---|
| `bin/omp-termux` | The entire tool (bash, hard tabs, ~820 lines). |
| `install.sh` | Device bootstrap: fetch raw `bin/omp-termux`, `bash -n` it, run device `install`. |
|`patches/`|Vendored upstream PR #6350 patch: attribution header, then 15 diffs over 15 files against v18.2.0.|
| `.github/workflows/build.yml` | The only CI: cross-compile and publish one release per omp version. |
| `docs/` | `README.zh-CN.md` (translation of `README.md`), `font.md` / `font.zh-CN.md` (Nerd Font notes). |
| `work/`, `out/` | Gitignored: upstream clone + cargo target + opus prefix + napi-cli; built artifacts. |

## Development Commands

```sh
bash -n bin/omp-termux && sh -n install.sh      # syntax gates (the only automated checks in-repo)
bash bin/omp-termux help                        # verb list = header lines 4-14, printed by usage()
bash bin/omp-termux doctor                      # toolchain / environment report
./bin/omp-termux build 18.1.19                  # cross-compile only (needs rustup + NDK + bun + cmake + ninja)
OMP_TERMUX_MODE=device bash bin/omp-termux build   # native build on a phone: hours, takes termux-wake-lock
bash bin/omp-termux device user@phone           # persist the ssh target in ~/.config/omp-termux/config
bash bin/omp-termux install 18.1.19             # workstation: build/upload/install/verify on the device
OMP_TERMUX_MODE=device bash bin/omp-termux install path/to/pi_natives.android-arm64.node
```

- CI is reproduced locally by `./bin/omp-termux build "$VERSION"` — nothing else runs there.
- One commit per meaningful change, conventional `type: subject` with a terse body; the released commit and
  its tag are never rewritten.
- `work/src` is a throwaway clone that `fetch_source` wipes or hard-resets: never hand-edit it.

## Code Conventions & Common Patterns

- `set -Eeuo pipefail` plus an `ERR` trap that prints `script:line:command`. With `pipefail`, any tolerated
  failure must be guarded (`|| true`, `|| warn …`).
- Reporting goes through `msg` (stdout, `==>`), `warn` (stderr, non-fatal), `die` (stderr, `exit 1`). Tests use
  `[ … ]`, never `[[ … ]]`; output is `printf`.
- Function shape: `name() {` on its own line, `local` first, `# $1 = …` doc-comment on the definition line,
  sections separated by `# --- name ---` banners padded to ~100 columns.
- Comments are reserved for non-obvious external constraints — the loader's sentinel rule, the bun
  cache/global layout, `audiopus_sys` having no `rerun-if-env-changed`, opus' CMake predating CMake 4, the
  `sh -c` wrapping because the device login shell may be fish. Never restate code.
- The header block (lines 4-14) **is** the help text: `usage()` is `sed -n '4,14p' "$SELF"`. Adding a verb means
  editing that range too.
- Idempotency is a requirement, not a nicety: `cmd_install_self` skips copying onto itself, `link_global_tree`
  only refreshes symlinks and never clobbers real directories, `apply_patch` greps for its marker, `update-self`
  runs `bash -n` + sha256 + `mv` before replacing.
- Device-facing helpers: `device_ssh` (wraps every command in `sh -c $(printf %q …)`), `device_scp` (retries with
  `-O`), `device_run` (forces `OMP_TERMUX_MODE=device`, removes `~/$SCRATCH` in the same session, interpolates its
  argument as a command line — pass shell-safe strings only).
- Environment inputs are `OMP_TERMUX_*` (`MODE`, `HOST`, `PORT`, `NDK`, `REPO`, `RELEASE_BASE`, `RAW_BASE`,
  `VERSION`, `NO_UPDATE_CHECK`, `UPDATE_TTL`); the device must never need an export to work — defaults plus the
  saved config file cover it.
- Argument hygiene: `install`, `build` and `device` reject a leading `-`; `device` also validates the target
  against `[A-Za-z0-9._@:-]`. Extending option parsing means extending those checks.
- Own the two-mode contract in one place: workstation verbs shell out to the device, device verbs act locally.
  If a verb only makes sense on one side, say so in the header help text rather than silently half-working.
  `install latest` is the one place where the two sides mean different things on purpose: on the device it is
  the newest build *this repository* publishes (the only thing a device can be brought to), on the workstation
  the newest upstream release, which it builds from source.
- `check_self_update` runs before every verb except `help` and `update-self`, and only when the running file is
  the installed copy. It compares the content hash of `main` (conditional GET, `ETag`) with its own, caches the
  result for `OMP_TERMUX_UPDATE_TTL` seconds under `$PREFIX/cache/self-update` so most verbs never talk to the
  network, and prints one line to stderr when they differ. It never writes to stdout and never changes an exit
  code; the cache is also where `status` gets its `newest here` line. The version lookup resolves
  `<repo>/releases/latest`'s 302 instead of the GitHub API: the API's 60 requests per hour are per IP and a
  phone behind carrier NAT shares that with strangers, and a 403 used to be indistinguishable from "no newer
  release".
- Docs (`README.md`, `docs/*.md`) are a bilingual pair-set with **English canonical**: prose is translated, while
  every command, flag, path, env var, file name, error string and fenced code block stays byte-identical between
  the two files. Content may differ only where the audience differs (today: the `-CN` font variant exists only in
  the Chinese font doc). Keep the language switcher on line 3, prose lines broken after punctuation (`。,:;、`)
  and never left ending on a CJK function word, and no personal paths, usernames or e-mail addresses anywhere.
- Docs describe what a user does and sees. Do not document build mechanics, CI cadence, internal cache paths or
  loader internals there; that knowledge belongs in the code comment next to the mechanism.

## Important Files

- `bin/omp-termux` globals (near the top): `TERMUX_PREFIX` is captured **before** `PREFIX` is reused as the
  tool's own prefix (reordering breaks device install paths); `SCRATCH` is relative to `$HOME` on the device;
  `ADDON=pi_natives.android-arm64.node` is the loader-visible name used by install/build/fetch/upload/verify;
  `API=24`, `UPSTREAM`, `PR=6350`, `PR_PATCH_URL`, `REPO`, `WORK`/`OUT`/`SRC`/`NAPI_CLI_DIR`/`OPUS_PREFIX`.
- `bin/omp-termux`'s own identity and update state: `TOOL_VERSION` (0.1.0, a human label only — every
  comparison reads the content hash), `SELF_URL` (raw `main`, shared with `cmd_update_self`), `SELF_CACHE`
  (`$PREFIX/cache/self-update`, removed by `uninstall-self` together with the prefix) and `SELF_TTL`.
- Environment resolution lives in one place per side: `bun_root` (bun's rule for a *new* root), `bun_roots`,
  `bun_active_root` (the root in use), `use_root` and `omp_path`; the device twins are `REMOTE_ROOT_PROBE`
  with `remote_bun_root`/`remote_bun_env`. Installing, version lookup and the smoke test read these.
- Key functions: `usage`, `install_addon`, `link_global_tree`, `fetch_release`, `device_install`, `run_verify`,
  `installed_state`/`newest_natives_dir` (what the device actually loads), `check_self_update`, `cache_get`/
  `cache_put`, `fetch_source`, `apply_patch`, `prepare_opus`, `cross_build`, `finalize_artifact`,
  `verify_artifact`, `resolve_target`, `workstation_install`, `install_on_device`, `cmd_install_self`,
  `cmd_update_self`, `cmd_uninstall_self`, plus the dispatch `case` (line numbers drift; search by name).
- Contracts worth re-reading before an edit: `fetch_release` removes the scratch dir before `die` so a missing
  release changes nothing, and it only accepts an addon whose embedded sentinel equals the requested version;
  `device_install` fetches the addon **before** upgrading omp, resolves `latest` from this repository's newest
  published release, skips everything (download included) when that version is already installed and loads, and
  fails only when the installed version is newer than anything published here; `verify_artifact` hard-fails on
  non-`ARM aarch64`, any `GLIBC_` need, or `libc.so.6`/`ld-linux` NEEDED entries.
- Cross-file couplings: asset names (`build.yml` ⇄ `$ADDON` ⇄ `fetch_release` ⇄ `finalize_artifact`), tag naming
  `omp-<version>` (workflow trigger, skip guard, download URL), URL bases (`REPO`/raw base in `install.sh` and
  the script), cache paths in CI mirroring `WORK`/`CARGO_TARGET`/`NAPI_CLI_DIR`/`OPUS_PREFIX`/`SRC`, and
  `PR=6350` matching the patch header, `LICENSE` footer and README credits, which is why `vendored_patch` only
  accepts a patch file whose header names the current `$PR`.

## Runtime/Tooling Preferences

- Device: bash + `bun` only (`curl`, `unzip` for the bun fallback). No rust, clang or NDK unless building there.
- Workstation: `rustup`, `bun` ≥ 1.3.14, an Android NDK, `cmake`, `ninja`, `git`, `curl`, `unzip`, `ssh`. NDK
  lookup order: `OMP_TERMUX_NDK` → `ANDROID_NDK_ROOT` → `ANDROID_NDK_HOME` → `ANDROID_NDK_LATEST_HOME` →
  `$ANDROID_HOME/ndk/*` (newest) → `/opt/android-ndk`; the host dir `toolchains/llvm/prebuilt/linux-x86_64` is
  hard-coded.
- bun's install root is resolved in one place (`bun_root`, `bun_roots`) and must never be hard-coded: it is
  `BUN_INSTALL`, else `$XDG_CACHE_HOME/.bun` when that variable is set, else `~/.bun`. Everything that touches
  the cache, the global tree or a bun binary goes through those helpers, and every root that exists is visited
  (a device that starts using XDG keeps a legacy `~/.bun` next to the new one).
- Rust channel and `@napi-rs/cli` version come from the upstream clone (`rust-toolchain.toml`,
  `package.json`) — never pin them here. CI pins `bun-version: 1` only.
- No package manager, lockfile, linter or formatter in this repo; no JS/TS sources of its own.

## Testing & QA

- `sh tests/verify.sh` is the local gate: syntax checks, then both modes against a fake device (stubbed
  `ssh`/`scp`/`bun`/`curl`, isolated `HOME`/`TMPDIR`/`XDG_CONFIG_HOME`/`FAKE_HOME`, `TERMUX_VERSION=0.118`). The
  device-side and workstation-side sections need `out/pi_natives.android-arm64.node` and are skipped without it.
  It never touches a real device or the network, and refuses to run if its `/tmp` paths are not what it expects.
- Extend that script whenever a bug escapes it: the harness is what caught the truncated `fetch_release`, the
  prune that deleted a link target and the `ln -sfn`-into-a-directory case, but the "no-argument install picked
  the oldest version" bug only showed up on a real device.
- CI has no test job: the only automated gates there are `bin/omp-termux build` and the in-script
  `verify_artifact` / `run_verify`.
- Contracts to assert after touching install/update code: unknown verbs and option-looking arguments exit 1;
  `install latest` on a device already at the published version exits 0, prints `nothing to do` and fetches
  nothing, while one that needs a download but has no release exits non-zero, calls no `bun install -g`, and
  prints `nothing was changed`; a device ahead of everything published here exits non-zero and leaves the addon
  untouched; an addon whose sentinel is not the requested version is rejected; repeated installs stay idempotent;
  the device end state is the addon plus `~/.local/opt/omp-termux` plus one symlink (`$PREFIX/bin/omp-termux` on
  Termux, `~/.local/bin` otherwise) and nothing else; `update-self` refuses a script that fails `bash -n` and
  keeps the old copy, and drops the self-update cache so the next verb re-checks.
- The self-update check is asserted through a stubbed `curl` that logs every call: one stderr line when `main`
  differs and none when it matches, no request at all while the cache is fresh or when
  `OMP_TERMUX_NO_UPDATE_CHECK` is set, and its scratch files never survive into `$TMPDIR`.
- Not verifiable without real hardware: bun's global layout behaviour on Android (the `link_global_tree` repair),
  the NDK cross-build, and anything touching `pkg`/`termux-*`.
- Doc statements are the user-visible contract — `README.md`'s Notes/Limitations must stay true (device keeps
  the addon and the tool; `uninstall-self` removes only the tool; arm64-v8a only; API 24 / Android 7+).
