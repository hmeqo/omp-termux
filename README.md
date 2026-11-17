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

The script:

1. installs bun if it is missing;
2. updates omp to the newest version built here;
3. copies the matching addon into the `native/` directory of the pi-natives package;
4. links `omp-termux` into `PATH`.

Arguments are passed through to `install`, so `... | sh -s -- 18.3.4` installs version 18.3.4.

If `omp` or `omp-termux` is still not found afterwards, the script offers to add them to your shell's startup file;
accept and open a new terminal.

Start `omp` to check the install; restart it if it was already running.

A newer `omp-termux` on `main` is reported on stderr on every run of `omp-termux` until you update it. Set
`OMP_TERMUX_NO_UPDATE_CHECK=1` to skip the check, or `OMP_TERMUX_UPDATE_TTL` (seconds, default 86400) to change how
often it queries. The check only requests `main` from GitHub; no telemetry or identifiers are sent.

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
* Nerd Font icons: [docs/user/font.md](docs/user/font.md) (or [中文](docs/user/font.zh-CN.md)).
* Termux pulls the view back to the bottom whenever `omp` writes to the terminal; try `tmux` (`Ctrl-b [`) or
  `SCROLL` (`⇳`) in Termux 0.119 and newer. omp 18.4.1 through 18.5.0 redraw once a second even while idle, so the
  view returns about a second after scrolling back.

## Limitations

* No desktop automation and no native clipboard on Android; the clipboard falls back to `termux-clipboard-set`.
* No audio, speech-to-text or text-to-speech on Android.
* Only arm64-v8a is supported; there is no build for armv7 or x86.

## Credits and license

Android support comes from upstream [PR #6350](https://github.com/can1357/oh-my-pi/pull/6350).
The upstream project is [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi); it and this repository are MIT —
see [LICENSE](LICENSE) for the attribution.
