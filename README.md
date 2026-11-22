# omp-termux

[English](README.md) | [中文](README.zh-CN.md)

`omp` depends on a native addon, `@oh-my-pi/pi-natives`, that upstream does not build for Android, so on Termux it
exits with `Unsupported platform: android-arm64`. This repository builds that addon for Termux and ships a small
`omp-termux` command that keeps omp and the addon on the same version.

## Requirements

- Android 7.0 or newer (API 24), aarch64
- `bash` and `curl`

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/hmeqo/omp-termux/main/install.sh | sh
```

To install a specific version, add it at the end:

```sh
curl -fsSL https://raw.githubusercontent.com/hmeqo/omp-termux/main/install.sh | sh -s -- 18.3.4
```

Start `omp` to check the install; restart it if it was already running. What the installer does, and how update
checks work: [docs/user/install.md](docs/user/install.md).

## Commands

| command | what it does |
|---|---|
| `omp-termux install [version\|file]` | install that version with its addon (`latest` = the newest build here, omitted = the version already installed); does nothing when it is current |
| `omp-termux status` | show the tool, omp, the addon copies and the newest build here |
| `omp-termux verify` | check that the addon loads and omp starts |
| `omp-termux update-self` | replace the installed `omp-termux` with the newest from this repository |
| `omp-termux uninstall-self` | remove the tool and its self-update cache from this device (omp stays) |
| `omp-termux doctor` | check the environment of this device |

## Caveats

* On Termux the screen scrolls from the top when the software keyboard opens;
  `omp config set tui.resizeScrollback preserve` avoids it.
* Nerd Font icons: [docs/user/font.md](docs/user/font.md).
* Termux pulls the view back to the bottom whenever `omp` writes to the terminal; try `tmux` (`Ctrl-b [`) or
  `SCROLL` (`⇳`) in Termux 0.119 and newer. omp 18.4.1 through 18.5.0 redraw once a second even while idle, so the
  view returns about a second after scrolling back.

## Limitations

* No desktop automation and no native clipboard on Android; the clipboard falls back to `termux-clipboard-set`.
* No audio, speech-to-text or text-to-speech on Android.
* Only arm64-v8a is supported; there is no build for armv7 or x86.

## Building the addon

`omp-termux-dev` cross-compiles the addon from a checkout and, with a device reachable over ssh, installs and
verifies it: [docs/dev/build.md](docs/dev/build.md). The device tool's design is
in [docs/dev/tool.md](docs/dev/tool.md).

## Credits and license

Android support comes from upstream [PR #6350](https://github.com/can1357/oh-my-pi/pull/6350).
The upstream project is [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi); it and this repository are MIT —
see [LICENSE](LICENSE) for the attribution.
