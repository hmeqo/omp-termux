# omp-termux

[English](README.md) | [中文](README.zh-CN.md)

`omp` needs a native addon (`@oh-my-pi/pi-natives`) that upstream does not build for Android, so on Termux it exits
with `Unsupported platform: android-arm64`. This repository installs that addon and gives you a small `omp-termux`
command to keep the two in step.

## Install

One command on Termux:

```sh
curl -fsSL https://raw.githubusercontent.com/hmeqo/omp-termux/main/install.sh | sh
```

Needs Android 7+ (API 24), aarch64 and `curl`. The script installs a missing `bun` and omp — the newest build
published here — then puts the addon matching your `@oh-my-pi/pi-natives` into the `native/` directory of the
package `omp` uses, and leaves `omp-termux` on your `PATH`. The bootstrap passes its arguments to `install`, so
`... | sh -s -- 18.3.4` installs that version.
Start `omp`, or restart it if it was already running: a successful start means the addon is in place.
Later, `omp-termux install latest` keeps the two in step.

A newer `omp-termux` on `main` is reported once on stderr; `OMP_TERMUX_NO_UPDATE_CHECK=1` silences that check
and `OMP_TERMUX_UPDATE_TTL` (seconds, default 86400) sets how often it runs.

## Commands

Device tool:

| command | what it does |
|---|---|
| `omp-termux install [version\|file]` | bring this device to that version and install the addon (`latest` = the newest build this repository publishes, default = the version it runs); skips the download when it is already there and provisions a bare device |
| `omp-termux status` | show the tool, omp, the addon copies and the newest build here |
| `omp-termux verify` | check that the addon loads and omp starts |
| `omp-termux update-self` | replace the installed `omp-termux` with the newest from this repository |
| `omp-termux uninstall-self` | remove the tool and its self-update cache from this device (omp stays) |
| `omp-termux doctor` | check the environment of this device |

Build half (from a checkout):

| command | what it does |
|---|---|
| `./dev/omp-termux-dev build [version]` | cross-compile the addon for android-arm64 |
| `./dev/omp-termux-dev install [version\|file]` | build when needed, upload, install and verify on the target device |
| `./dev/omp-termux-dev status` / `verify` | ask the target device what it runs / whether the addon loads |
| `./dev/omp-termux-dev device [user@host]` | show or save the target device |
| `./dev/omp-termux-dev doctor` | check what the build needs on this machine |

Building the addon: [Building the addon](docs/dev/build.md) (or [中文](docs/dev/build.zh-CN.md)).
The design behind the device tool: [The device tool](docs/dev/tool.md) (or [中文](docs/dev/tool.zh-CN.md)).

## Caveats

* On Termux the screen scrolls from the top when the software keyboard opens;
  `omp config set tui.resizeScrollback preserve` avoids it.
* omp draws its status line with Unicode symbols; for Nerd Font icons see [Nerd Font icons on Termux](docs/user/font.md)
  (or [中文](docs/user/font.zh-CN.md)).
* Termux pulls the view back to the bottom whenever `omp` writes to the terminal; if that gets in the way, try
  `tmux` (`Ctrl-b [`) or `SCROLL` (`⇳`) in Termux 0.119 and newer.
* omp 18.4.1 through 18.5.0 write to the terminal once a second even while idle, so the view returns about a second
  after scrolling back.

## Limitations

* No desktop automation and no native clipboard on Android; clipboard falls back to `termux-clipboard-set`.
* No audio, speech-to-text or text-to-speech on Android.
* Only arm64-v8a is built; armv7 and x86 emulators are untested.

## Privacy

No telemetry, no identifiers and no analytics. Every network request goes to one of these endpoints and carries
nothing beyond the request itself:

* `raw.githubusercontent.com/<repo>/main/...` for the bootstrap and the self-update check;
* `github.com/<repo>/releases/latest` for the redirect lookup that names the newest build here;
* `github.com/<upstream>/releases/latest` for the newest upstream omp release the build half targets;
* `github.com/<repo>/releases/download/omp-<ver>/...` for the addon;
* `github.com/oven-sh/bun/releases/latest/download/bun-linux-aarch64-android.zip` when bun is missing;
* `github.com/<upstream>.git` when the build half clones upstream, and
  `patch-diff.githubusercontent.com/raw/<upstream>/pull/6350.diff` when no vendored patch matches;
* ssh/scp to `OMP_TERMUX_HOST` when the build half drives a device.

`OMP_TERMUX_NO_UPDATE_CHECK=1` disables the self-update check; `OMP_TERMUX_UPDATE_TTL` controls how often it runs.

## Credits and license

Android support comes from upstream [PR #6350](https://github.com/can1357/oh-my-pi/pull/6350).
The upstream project is [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi);
both are MIT — see [LICENSE](LICENSE) for the attribution.
