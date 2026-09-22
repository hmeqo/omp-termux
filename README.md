# omp-termux

[English](README.md) | [中文](docs/README.zh-CN.md)

`omp` needs a native addon (`@oh-my-pi/pi-natives`) that upstream does not build for Android, so on Termux it exits
with `Unsupported platform: android-arm64`. This installs that addon and leaves a small `omp-termux` command
for keeping it in step.

## Install

### Prebuilt

On Termux, one command:

```sh
curl -fsSL https://raw.githubusercontent.com/hmeqo/omp-termux/main/install.sh | sh
```

Needs Android 7+ (API 24), aarch64 and `curl` (`unzip` only when `pkg install bun` fails). The script installs
a missing `bun` and omp — the newest build published here — then puts the matching addon in the `native/`
directory of the package `omp` uses. Start `omp`: a successful start means the addon is in place.

To move omp and its addon to the newest build published here:

```sh
omp-termux install latest   # omp + addon up to the newest build published here
omp-termux update-self      # replace omp-termux itself
```

### Build from source

On a workstation with the [development tools](#development) and `sshd` on the device (`pkg install openssh`):

```sh
omp-termux install-self         # once: put this tool on PATH (~/.local/bin)
omp-termux device user@phone    # once: remember the device (sshd, port 8022)
omp-termux install              # everything: build, transfer, install on the device, verify
omp-termux install latest       # later: upgrade omp on the device, then install the matching addon
```

## Development

Building from source needs a workstation (tested on Linux x86_64) with `rustup`, `bun` ≥ 1.3.14, an Android NDK
(taken from `OMP_TERMUX_NDK`, `ANDROID_NDK_ROOT`, `ANDROID_NDK_HOME` or your SDK's newest `ndk/*`), `cmake`,
`ninja`, `git`, `curl`, `unzip` and `ssh`. `omp-termux doctor` names whatever is missing.

## Commands

| command | what it does |
|---|---|
| `omp-termux install [version\|file]` | bring the device to that version and install the addon (`latest` = the newest build this repository publishes, default = the version it runs); skips the download when the device already carries it, builds only when needed, and provisions a bare device; on the workstation `latest` is the newest upstream release |
| `omp-termux status` / `verify` | show what is installed on the device / check that the addon loads |
| `omp-termux build [version]` | only produce the addon, without touching the device |
| `omp-termux device [user@host]` | show or save the device target |
| `omp-termux update-self` | replace the installed `omp-termux` with the newest from this repository |
| `omp-termux install-self` / `uninstall-self` | optional: keep this tool on PATH (`~/.local/opt/omp-termux`, `~/.local/bin/omp-termux`), or remove it |
| `omp-termux doctor` | check the cross toolchain |

## Notes

* The addon must match the version of `@oh-my-pi/pi-natives` you have; `omp-termux install` keeps them aligned.
* `omp-termux` prints one line to stderr when a newer copy of itself is on `main`;
  `OMP_TERMUX_NO_UPDATE_CHECK=1` turns that check off and `OMP_TERMUX_UPDATE_TTL` (seconds, default 86400)
  sets how often it runs.
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
