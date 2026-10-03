# Building the addon

[English](build.md) | [中文](build.zh-CN.md)

This is the maintainer's half of the repository: it produces the addon and, with the phone reachable over ssh,
puts it on the device and verifies it there. `bin/omp-termux` is the device tool; `dev/omp-termux-dev` is this
half, and sources it for the names and helpers both share.

## Requirements

A workstation (tested on Linux x86_64) with `rustup`, `bun` ≥ 1.3.14, an Android NDK (taken from
`OMP_TERMUX_NDK`, `ANDROID_NDK_ROOT`, `ANDROID_NDK_HOME` or your SDK's newest `ndk/*`), `cmake`, `ninja`, `git`,
`curl` and `unzip`. `./dev/omp-termux-dev doctor` names whatever is missing.

## Build

```sh
./dev/omp-termux-dev build 18.3.4   # cross-compiles out/pi_natives.android-arm64.node
```

Without a version it builds the newest upstream release, on a workstation or natively on the device (hours,
inside `tmux`).

## Put it on a device

```sh
./dev/omp-termux-dev device user@host     # save the target (~/.config/omp-termux/config)
./dev/omp-termux-dev install 18.3.4       # build when needed, upload, install and verify there
./dev/omp-termux-dev status               # what the device runs
```

`./dev/omp-termux-dev help` lists every verb (`build`, `install`, `status`, `verify`, `device`, `doctor`).
