# omp-termux

[English](README.md) | [中文](docs/README.zh-CN.md)

`omp` needs a native addon (`@oh-my-pi/pi-natives`) that upstream does not build for Android, so on Termux it exits
with `Unsupported platform: android-arm64`. This installs that addon and leaves a small `omp-termux` command
for keeping it in step.

## Install

### Prebuilt

Needs Termux with `bun` and omp already installed there (`bun install -g @oh-my-pi/pi-coding-agent`).

```sh
curl -fsSL https://raw.githubusercontent.com/hmeqo/omp-termux/main/install.sh | sh
```

The script installs `omp-termux` and puts the addon matching your omp version in the `native/` directory
of the package `omp` uses:

```sh
omp-termux install          # after you upgraded omp yourself: put the matching addon back
omp-termux install latest   # upgrade omp to the newest release, with the matching addon
omp-termux update-self      # replace omp-termux itself
```

Start `omp` afterwards: if it runs, the addon is in place. If your version is not available yet, try again
later, or use the method below.

### Build from source

On a workstation with the tools listed under [Requirements](#requirements):

```sh
omp-termux install-self         # once: put this tool on PATH (~/.local/bin)
omp-termux device user@phone    # once: remember the device (sshd, port 8022)
omp-termux install              # everything: build, transfer, install on the device, verify
omp-termux install latest       # later: upgrade omp on the device, then install the matching addon
```

## Requirements

Workstation (tested on Linux x86_64): `rustup`, `bun` ≥ 1.3.14, an Android NDK
(taken from `OMP_TERMUX_NDK`, `ANDROID_NDK_ROOT`, `ANDROID_NDK_HOME` or your SDK's newest `ndk/*`), `cmake`,
`ninja`, `git`, `curl`, `unzip`, `ssh`. `omp-termux doctor` names whatever is missing.

Device: Android 7+ (API 24), aarch64, with `sshd` (`pkg install openssh`). bun and omp are installed
automatically by `omp-termux install`.

## Commands

| command | what it does |
|---|---|
| `omp-termux install [version\|file]` | bring the device to that version and install the addon (`latest` = newest upstream release, default = the version it runs); builds only when needed and provisions a bare device; on the device, the same, for itself |
| `omp-termux status` / `verify` | show what is installed on the device / check that the addon loads |
| `omp-termux build [version]` | only produce the addon, without touching the device |
| `omp-termux device [user@host]` | show or save the device target |
| `omp-termux update-self` | replace the installed `omp-termux` with the newest from this repository |
| `omp-termux install-self` / `uninstall-self` | optional: keep this tool on PATH (`~/.local/opt/omp-termux`, `~/.local/bin/omp-termux`), or remove it |
| `omp-termux doctor` | check the cross toolchain |

## Notes

* The addon must match the version of `@oh-my-pi/pi-natives` you have; `omp-termux install` keeps them aligned.
* The device keeps the addon and `omp-termux`; `omp-termux uninstall-self` removes the tool and leaves omp alone.
* Restart `omp` after installing: a running one keeps using the old addon.
* On Termux the screen scrolls from the top when the software keyboard opens;
  `omp config set tui.resizeScrollback preserve` avoids it.
* omp draws its status line with Unicode symbols; for Nerd Font icons see [Nerd Font icons on Termux](docs/font.md)
  (or [中文](docs/font.zh-CN.md)).

## Limitations

* No desktop automation and no native clipboard on Android; clipboard falls back to `termux-clipboard-set`.
* No audio, speech-to-text or text-to-speech on Android.
* Only arm64-v8a is built; armv7 and x86 emulators are untested.

## Credits and license

Android support comes from upstream [PR #6350](https://github.com/can1357/oh-my-pi/pull/6350)
by [@anatoli-tsinovoy](https://github.com/anatoli-tsinovoy).
The upstream project is [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi);
both are MIT — see [LICENSE](LICENSE).
