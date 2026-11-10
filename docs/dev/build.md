# Building the addon

[English](build.md) | [中文](build.zh-CN.md)

`dev/omp-termux-dev` cross-compiles the addon from a checkout and, with the device reachable over ssh, installs and
verifies it there. It is the build half; the device tool is described in [The device tool](tool.md).

## Requirements

A workstation (tested on Linux x86_64) with `rustup`, `bun` ≥ 1.3.14, an Android NDK (taken from
`OMP_TERMUX_NDK`, `ANDROID_NDK_ROOT`, `ANDROID_NDK_HOME` or your SDK's newest `ndk/*`), `cmake`, `ninja`, `git`,
`curl`, `unzip`, and `file` plus `readelf` for the artifact checks (`nm` is used when present). The NDK is the
system's business: whatever the SDK, a package manager or the environment already provides is used, and no copy is
shipped here. `./dev/omp-termux-dev doctor` names whatever is missing.

## Build

```sh
./dev/omp-termux-dev build 18.3.4   # cross-compiles out/pi_natives.android-arm64.node
```

Without a version it builds the newest upstream release on a workstation; natively on the device it builds the
version the device runs (hours, inside `tmux`). The same verbs mean different things in the two modes: `OMP_TERMUX_MODE` overrides the detection,
and the verbs that drive a target device over ssh refuse in device mode.

## Source, patch and dependencies

`fetch_source` clones upstream at tag `v<version>` into `work/src`, a throwaway clone that is wiped or hard-reset
and never hand-edited. `apply_patch` applies the vendored `patches/*.patch` strictly with `git apply` (no fuzz, no
3-way) and checks the marker the patch has to change; a file is eligible only when its header names the current
PR, so a stale patch cannot be applied after a PR bump. Without an eligible file, the PR diff is downloaded.

`@napi-rs/cli` is installed standalone into `work/napi-cli` at the version upstream's `package.json` declares: a
plain `bun install` in `packages/natives` would resolve the whole monorepo (~400 packages, ~1.5 GB), while the CLI
alone is ~56 MB. A device build resolves the CLI from `packages/natives/node_modules`; the workstation path
symlinks that to the standalone copy and installs into a real tree when one exists.

## The opus path

Up to omp 18.1.22 the `opus` crate vendored its sources through `audiopus_sys`. Since 18.2.0 it uses `opusic-sys`,
whose default `bundled` feature builds opus with cmake from its own tree; nothing consumes the libopus built here,
and on a clean machine the `audiopus_sys` sources are not fetched at all. `prepare_opus` therefore runs only when
`Cargo.lock` still carries `audiopus_sys`, and it removes the crate's build directory first because the crate
declares no `rerun-if-env-changed` and Cargo would reuse the rlib left by a host-ABI run.

## The cross-build

`cross_build` drives the napi CLI with `--target aarch64-linux-android --profile ci` into `out/.build`, with the
NDK named three ways (`ANDROID_NDK_LATEST_HOME`, `ANDROID_NDK_HOME`, `ANDROID_NDK_ROOT`), `ANDROID_PLATFORM` at
API 24, and `BINDGEN_EXTRA_CLANG_ARGS_*` pointing at the sysroot. `RUSTC_BOOTSTRAP` is scoped to `xutf,pi_natives`
so the N-API crates build on the stable rustc a device carries.

## Artifact identity

The loader compares `__piNativesBuildVersion()` with the package version, and release sources leave that 64-byte
slot empty: upstream stamps it after linking. The workstation path runs upstream's `scripts/stamp-native-version.ts`
itself; a release without that tool is a pre-slot one and needs no stamp. `finalize_artifact` finds the produced
`pi_natives*.node`, stamps it, verifies it, and only then replaces `out/pi_natives.android-arm64.node`, so a failed
run leaves the previous good artifact in place.

`verify_artifact` fails on anything that is not `ARM aarch64`, on a missing `.note.android.ident`, on `GLIBC_*`
version needs, and on `libc.so.6`/`ld-linux` NEEDED entries. It also checks the N-API entrypoint and that the
artifact reports the requested release.

## Put it on a device

```sh
./dev/omp-termux-dev device user@host     # save the target (~/.config/omp-termux/config)
./dev/omp-termux-dev install 18.3.4       # build when needed, upload, install and verify there
./dev/omp-termux-dev status               # what the device runs
```

The target is `OMP_TERMUX_HOST`/`OMP_TERMUX_PORT`, else the saved `~/.config/omp-termux/config`. The port falls
back to what `ssh -G` reports; 22 means ssh's own default with nothing configured, which is not a Termux port, so
8022 is used then.

Every remote command runs as `sh -c` through ssh, because sshd would otherwise use the login shell (fish, zsh, ...)
and the snippets are POSIX.

`install` (and `status`/`verify`) uploads `bin/omp-termux` once per run into `~/.cache/omp-termux/build` on the
device, under `OMP_TERMUX_CACHE_HOME` when that is set and relative to the device's `HOME` unless the value is
absolute. An EXIT trap removes that directory and the now-empty parent. With no argument, `install` asks the staged
tool's `status` for the `omp` row — the version to build; a device with no omp gets the newest upstream release.
There is no bun or omp logic here: the staged tool resolves its own root and provisions the device.

`install` first stages only the tool and reads the device status, then builds or stages the artifact: a cold
build fails before anything on the device changes. It uploads the artifact into the same scratch directory, runs
`install "<file>"` through the staged tool, then `verify`; `status` and `verify` are the same round trip without
changing anything.

## Publish

`.github/workflows/build.yml` is the only CI. It runs `./dev/omp-termux-dev build "$VERSION"` and publishes release
`omp-<version>` carrying `out/pi_natives.android-arm64.node`; one release per omp version, because the addon only
lands in the package whose version it reports. There is no verification CI: the local gate is `sh tests/verify.sh`.
