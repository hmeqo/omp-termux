# omp-termux

[English](README.md) | [中文](README.zh-CN.md)

`omp` needs a native addon (`@oh-my-pi/pi-natives`) that upstream does not build for Android, so on Termux it exits
with `Unsupported platform: android-arm64`. This repository supplies that addon and a small `omp-termux` command that
keeps omp and the addon on the same version.

## Install

On Termux:

```sh
curl -fsSL https://raw.githubusercontent.com/hmeqo/omp-termux/main/install.sh | sh
```

Needs Android 7+ (API 24), aarch64, `bash` and `curl`. The script installs bun when missing, sets omp to the newest
version built here, copies the matching addon into the `native/` directory of the pi-natives package, and links
`omp-termux` into `PATH`. Arguments go to `install`: `... | sh -s -- 18.3.4` installs that version.

Start `omp`, or restart it if it was already running: a successful start means the addon is in place.

A newer `omp-termux` on `main` is reported on stderr on every run until you update it. `OMP_TERMUX_NO_UPDATE_CHECK=1`
silences that check and `OMP_TERMUX_UPDATE_TTL` (seconds, default 86400) sets how often it looks. The update check
asks GitHub for `main`; no telemetry or identifiers are sent.

## Commands

| command | what it does |
|---|---|
| `omp-termux install [version\|file]` | bring this device to that version and install the addon (`latest` = the newest build here, default = the version it runs); no-op when already current |
| `omp-termux status` | show the tool, omp, the addon copies and the newest build here |
| `omp-termux verify` | check that the addon loads and omp starts |
| `omp-termux update-self` | replace the installed `omp-termux` with the newest from this repository |
| `omp-termux uninstall-self` | remove the tool and its self-update cache from this device (omp stays) |
| `omp-termux doctor` | check the environment of this device |

## Caveats

* On Termux the screen scrolls from the top when the software keyboard opens;
  `omp config set tui.resizeScrollback preserve` avoids it.
* Nerd Font icons: [docs/user/font.md](docs/user/font.md) (or [中文](docs/user/font.zh-CN.md)).
* Termux pulls the view back to the bottom whenever `omp` writes to the terminal; try `tmux` (`Ctrl-b [`) or
  `SCROLL` (`⇳`) in Termux 0.119 and newer. omp 18.4.1 through 18.5.0 redraw once a second even while idle, so the
  view returns about a second after scrolling back.

## Limitations

* No desktop automation and no native clipboard on Android; clipboard falls back to `termux-clipboard-set`.
* No audio, speech-to-text or text-to-speech on Android.
* Only arm64-v8a is supported; there is no build for armv7 or x86.

## Credits and license

Android support comes from upstream [PR #6350](https://github.com/can1357/oh-my-pi/pull/6350).
The upstream project is [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi); it and this repository are MIT —
see [LICENSE](LICENSE) for the attribution.
