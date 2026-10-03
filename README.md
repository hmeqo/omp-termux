# omp-termux

[English](README.md) | [中文](docs/README.zh-CN.md)

`omp` needs a native addon (`@oh-my-pi/pi-natives`) that upstream does not build for Android, so on Termux it exits
with `Unsupported platform: android-arm64`. This repository installs that addon and gives you a small `omp-termux`
command to keep the two in step.

## Install

### On Termux

One command:

```sh
curl -fsSL https://raw.githubusercontent.com/hmeqo/omp-termux/main/install.sh | sh
```

Needs Android 7+ (API 24), aarch64 and `curl`. The script installs a missing `bun` and omp — the newest build
published here — then puts the addon matching your `@oh-my-pi/pi-natives` into the `native/` directory of the
package `omp` uses, and leaves `omp-termux` on your PATH. Start `omp`, or restart it if it was already running:
a successful start means the addon is in place. Later, `omp-termux install latest` keeps the two in step.

### Keep it in step

```sh
omp-termux install latest   # omp + addon up to the newest build published here
omp-termux update-self      # replace omp-termux itself
```

A newer `omp-termux` on `main` is reported once on stderr; `OMP_TERMUX_NO_UPDATE_CHECK=1` silences that check
and `OMP_TERMUX_UPDATE_TTL` (seconds, default 86400) sets how often it runs.

## Commands

| command | what it does |
|---|---|
| `omp-termux install [version\|file]` | bring this device to that version and install the addon (`latest` = the newest build this repository publishes, default = the version it runs); skips the download when it is already there, builds only when needed, and provisions a bare device |
| `omp-termux status` / `verify` | show what is installed / check that the addon loads |
| `omp-termux update-self` | replace the installed `omp-termux` with the newest from this repository |
| `omp-termux uninstall-self` | remove the tool and its cache from this device (omp stays) |
| `omp-termux doctor` | check the environment of this device |

Building the addon from source is the other half of the repository: [Building the addon](docs/build.md)
(or [中文](docs/build.zh-CN.md)).

## Caveats

* Since omp 18.4.1, `omp` writes to the terminal about once a second even when idle, and Termux pulls the view back
  to the bottom on every write: read back in `tmux` (`Ctrl-b [`) or with `SCROLL` (`⇳`) in Termux 0.119 and newer.
  The software keyboard does the same on resize; `omp config set tui.resizeScrollback preserve` avoids that.
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
