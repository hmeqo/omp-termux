# Building the addon

[English](build.md) | [中文](build.zh-CN.md)

`dev/omp-termux-dev` cross-compiles the addon from a checkout and, with the device reachable over ssh, installs and
verifies it there. The device-side tool is described in [the device tool](tool.md).

## Requirements

A workstation (tested on Linux x86_64) with `rustup`, `bun` ≥ 1.3.14, `cmake`, `ninja`, `git`, `curl`, `unzip`, and
`file` with `readelf` for the artifact checks (`nm` is optional). The NDK is taken from, in this order:

1. `OMP_TERMUX_NDK`, `ANDROID_NDK_ROOT`, `ANDROID_NDK_HOME`, `ANDROID_NDK_LATEST_HOME`;
2. the newest `ndk/*` under `ANDROID_HOME`, `~/Android/Sdk`, `~/.local/share/Android/Sdk`, `/opt/android-sdk`;
3. `/opt/android-ndk`, `~/.local/share/android-ndk`.

`./dev/omp-termux-dev doctor` names whatever is missing.

## Build

```sh
./dev/omp-termux-dev build 18.3.4   # cross-compiles out/pi_natives.android-arm64.node
```

Without a version it builds the newest upstream release. Run on a device, it builds the pi-natives version installed
there instead (hours; run it inside `tmux`). `OMP_TERMUX_MODE` overrides that detection, and the verbs that reach a
device over ssh refuse in device mode.

## Source and patch

`fetch_source` clones upstream at tag `v<version>` into `work/src`, a throwaway clone that is wiped or hard-reset and
never hand-edited. `apply_patch` applies the vendored `patches/*.patch` strictly with `git apply` (no fuzz, no 3-way)
and checks the marker the patch has to change; a file is eligible only when its header names the current PR. Without
an eligible file, the PR diff is downloaded.

## The napi CLI

`@napi-rs/cli` is installed standalone into `work/napi-cli` at the version upstream's `package.json` declares: a plain
`bun install` in `packages/natives` would resolve the whole monorepo (~400 packages, ~1.5 GB), while the CLI alone is
~56 MB. A device build resolves the CLI from `packages/natives/node_modules`; the workstation path symlinks that to
the standalone copy and installs into a real tree when one exists.

## Opus

`prepare_opus` runs only when `Cargo.lock` still carries `audiopus_sys`: those releases vendor opus through it, and
`cross_build` then links `$OPUS_PREFIX` via `LIBOPUS_LIB_DIR`. Newer releases use `opusic-sys`, whose default
`bundled` feature builds opus from its own tree with cmake. The step removes the crate's build directory first,
because the crate declares no `rerun-if-env-changed` and Cargo would reuse the rlib left by a host-ABI run.

## The cross-build

`cross_build` drives the napi CLI with `--target aarch64-linux-android --profile ci` into `out/.build`, with the NDK
named three ways (`ANDROID_NDK_LATEST_HOME`, `ANDROID_NDK_HOME`, `ANDROID_NDK_ROOT`), `ANDROID_PLATFORM` at API 24,
and `BINDGEN_EXTRA_CLANG_ARGS_*` pointing at the sysroot. `RUSTC_BOOTSTRAP` is scoped to `xutf,pi_natives` so the
N-API crates build on the stable rustc a device carries.

## Artifact identity

The loader compares `__piNativesBuildVersion()` with the package version, and release sources leave that 64-byte slot
empty: upstream stamps it after linking. The workstation path runs upstream's `scripts/stamp-native-version.ts`
itself; a release without that tool must already report its version another way. `finalize_artifact` finds the
produced `pi_natives*.node`, stamps it, verifies it, and only then replaces `out/pi_natives.android-arm64.node`, so a
failed run leaves the previous good artifact in place.

## Artifact checks

`verify_artifact` fails on anything that is not `ARM aarch64`, on a missing `.note.android.ident`, on `GLIBC_*`
version needs, and on `libc.so.6`/`ld-linux` NEEDED entries. It also checks the N-API entrypoint and that the artifact
reports the requested release.

## Device

```sh
./dev/omp-termux-dev device user@host     # save the target ($XDG_CONFIG_HOME/omp-termux/config)
./dev/omp-termux-dev install 18.3.4       # build when needed, upload, install and verify there
./dev/omp-termux-dev status               # what the device runs
```

The target is `OMP_TERMUX_HOST`/`OMP_TERMUX_PORT`, else the saved file. The port falls back to what `ssh -G` reports;
22 is ssh's own default with nothing configured, not a Termux port, so 8022 is used then. Every remote command runs
through `sh -c`, because sshd would otherwise use the login shell (fish, zsh, ...) and the snippets are POSIX.

Each run uploads `bin/omp-termux` once into `~/.cache/omp-termux/build` on the device; `OMP_TERMUX_CACHE_HOME` from
the workstation environment moves that directory, and a relative value resolves against the device's `HOME`. An EXIT
trap removes it and the now-empty parent. `install` stages the tool first and reads its `status` for the `omp` row —
the version to build, or the newest upstream release when the device has no omp — so a failed cold build changes
nothing there. It then builds or stages the artifact, uploads it to the same directory, runs `install "<file>"`
through the staged tool, and ends with `verify`. `status` and `verify` are the same round trip without changing
anything; the staged tool resolves the device's bun and omp itself.

## Publish

`.github/workflows/build.yml` is the only CI. It runs `./dev/omp-termux-dev build "$VERSION"` and publishes release
`omp-<version>` carrying `out/pi_natives.android-arm64.node`, one release per omp version. There is no verification
CI: the local gate is `sh tests/verify.sh`.
