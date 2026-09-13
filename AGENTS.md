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
  or `/data/data/com.termux/files/usr` present ⇒ device; `OMP_TERMUX_MODE` overrides). ~60 helper functions sit
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
| `patches/` | Vendored upstream PR #6350 patch: hand-written attribution header, then 16 diffs over 17 files. |
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
- History is one squashed commit: amend it instead of adding commits, and keep the message in `feat:`/body form.
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
  `VERSION`); the device must never need an export to work — defaults plus the saved config file cover it.
- Argument hygiene: `install`, `build` and `device` reject a leading `-`; `device` also validates the target
  against `[A-Za-z0-9._@:-]`. Extending option parsing means extending those checks.
- Own the two-mode contract in one place: workstation verbs shell out to the device, device verbs act locally.
  If a verb only makes sense on one side, say so in the header help text rather than silently half-working.
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
- Key functions: `usage`, `install_addon`, `link_global_tree`, `fetch_release`, `device_install`, `run_verify`,
  `fetch_source`, `apply_patch`, `prepare_opus`, `cross_build`, `finalize_artifact`, `verify_artifact`,
  `resolve_target`, `workstation_install`, `install_on_device`, `cmd_install_self`, `cmd_update_self`,
  `cmd_uninstall_self`, plus the dispatch `case` (line numbers drift; search by name).
- Contracts worth re-reading before an edit: `fetch_release` removes the scratch dir before `die` so a missing
  release changes nothing; `device_install` fetches the addon **before** upgrading omp; `verify_artifact`
  hard-fails on non-`ARM aarch64`, any `GLIBC_` need, or `libc.so.6`/`ld-linux` NEEDED entries.
- Cross-file couplings: asset names (`build.yml` ⇄ `$ADDON` ⇄ `fetch_release` ⇄ `finalize_artifact`), tag naming
  `omp-<version>` (workflow trigger, skip guard, download URL), URL bases (`REPO`/raw base in `install.sh` and
  the script), cache paths in CI mirroring `WORK`/`CARGO_TARGET`/`NAPI_CLI_DIR`/`OPUS_PREFIX`/`SRC`, and
  `PR=6350` matching the patch header, `LICENSE` footer and README credits.

## Runtime/Tooling Preferences

- Device: bash + `bun` only (`curl`, `unzip` for the bun fallback). No rust, clang or NDK unless building there.
- Workstation: `rustup`, `bun` ≥ 1.3.14, an Android NDK, `cmake`, `ninja`, `git`, `curl`, `unzip`, `ssh`. NDK
  lookup order: `OMP_TERMUX_NDK` → `ANDROID_NDK_ROOT` → `ANDROID_NDK_HOME` → `ANDROID_NDK_LATEST_HOME` →
  `$ANDROID_HOME/ndk/*` (newest) → `/opt/android-ndk`; the host dir `toolchains/llvm/prebuilt/linux-x86_64` is
  hard-coded.
- Rust channel and `@napi-rs/cli` version come from the upstream clone (`rust-toolchain.toml`,
  `package.json`) — never pin them here. CI pins `bun-version: 1` only.
- No package manager, lockfile, linter or formatter in this repo; no JS/TS sources of its own.

## Testing & QA

- There is no test suite, no linter and no test job in CI. The only automated gates are the syntax checks, CI's
  `bin/omp-termux build` and the in-script `verify_artifact` / `run_verify`.
- After a change, at minimum: `bash -n bin/omp-termux`, `sh -n install.sh`, and exercise the touched verb in a
  **fake-device harness** — stub `ssh`/`scp`/`bun`/`curl` first on `PATH`, isolate `HOME`, `TMPDIR`,
  `XDG_CONFIG_HOME` and a `FAKE_HOME`, force `TERMUX_VERSION=0.118` for device mode. Never point a test at a real
  device and never let it need the network; a fake `ssh` that re-runs the remote command with `HOME=$FAKE_HOME`
  is enough to cover both modes.
- Contracts to assert after touching install/update code: unknown verbs and option-looking arguments exit 1;
  `install latest` with a missing release exits non-zero, calls no `bun install -g`, and prints
  `nothing was changed`; repeated installs stay idempotent; the device end state is the addon plus
  `~/.local/opt/omp-termux` plus one symlink (`$PREFIX/bin/omp-termux` on Termux, `~/.local/bin` otherwise) and
  nothing else; `update-self` refuses a script that fails `bash -n` and keeps the old copy.
- Not verifiable without real hardware: bun's global layout behaviour on Android (the `link_global_tree` repair),
  the NDK cross-build, and anything touching `pkg`/`termux-*`.
- Doc statements are the user-visible contract — `README.md`'s Notes/Limitations must stay true (device keeps
  the addon and the tool; `uninstall-self` removes only the tool; arm64-v8a only; API 24 / Android 7+).
