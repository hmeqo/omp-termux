# The build half: design notes

[English](build.md) | [中文](build.zh-CN.md)

This records what `dev/omp-termux-dev` does and why. What a maintainer runs is in `../build.md`; the device tool is
`tool.md`.

## Where it runs

The same verbs mean different things on a workstation and on a device, so this half asks where it is (Termux
detection, with `OMP_TERMUX_MODE` as the override). On a device `build` is a native build through upstream's
`packages/natives/scripts/build-bindings.ts`; on a workstation it is a cross-compile. The verbs that drive a target
device over ssh refuse in device mode.

## Source, patch and dependencies

`fetch_source` clones upstream at tag `v<version>` into `work/src`, a throwaway clone that is wiped or hard-reset
and never hand-edited. `apply_patch` applies the vendored patch strictly with `git apply` (no fuzz, no 3-way) and
checks the marker the patch has to change; a patch file is only eligible when its header names the current PR, so a
stale file cannot be applied after a PR bump. Without a vendored file, the PR diff is downloaded.

`@napi-rs/cli` is installed standalone into `work/napi-cli` at the version upstream's `package.json` declares: a
plain `bun install` in `packages/natives` would resolve the whole monorepo (~400 packages, ~1.5 GB), while the CLI
alone costs ~67 packages. A device build runs `build-bindings.ts` from the source tree and resolves the CLI from
`packages/natives/node_modules`; the workstation path symlinks that to the standalone copy and installs into a real
tree when one exists.

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

## Device access

The target is `OMP_TERMUX_HOST`/`OMP_TERMUX_PORT`, else the saved `~/.config/omp-termux/config`. The port falls
back to what `ssh -G` reports; 22 means ssh's own default with nothing configured, which is not a Termux port, so
8022 is used then.

Every remote command runs as `sh -c` through ssh, because sshd would otherwise use the login shell (fish, zsh, ...)
and the snippets are POSIX. The scratch directory is relative to the device's `HOME` unless an absolute path is
given; it is created for the run, holds the uploaded addon and tool, and is removed afterwards.

`install` builds or stages the artifact before it touches the device, so a cold build fails there and not halfway
through an upload. It then brings the device's omp to that version, uploads the artifact and the tool, and lets
the tool install on the far side: the change being exercised is the tool itself, so the device runs the copy from
this checkout. `status` and `verify` are the same round trip without changing anything.
