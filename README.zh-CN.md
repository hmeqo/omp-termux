# omp-termux

[English](README.md) | [中文](README.zh-CN.md)

`omp` 需要原生插件 `@oh-my-pi/pi-natives`,上游没有为 Android 构建它,因此在 Termux 上会报错退出:
`Unsupported platform: android-arm64`。本仓库提供这个插件,并提供一个 `omp-termux` 命令,让 omp 与插件保持同一版本。

## 安装

在 Termux 上:

```sh
curl -fsSL https://raw.githubusercontent.com/hmeqo/omp-termux/main/install.sh | sh
```

设备要求 Android 7+(API 24)、aarch64,并装有 `bash` 与 `curl`。
脚本会在缺少 bun 时装上它,把 omp 升到本仓库构建的最新版本,
把匹配的插件复制进 pi-natives 包的 `native/` 目录,并把 `omp-termux` 链接进 `PATH`。
参数会转交给 `install`: `... | sh -s -- 18.3.4` 会安装该版本。

能正常启动就说明插件已就位(已在运行则重启)。

`main` 上有更新的 `omp-termux` 时,每次运行都会在 stderr 提示一行,直到你更新它。
`OMP_TERMUX_NO_UPDATE_CHECK=1` 可关闭该检查,`OMP_TERMUX_UPDATE_TTL`(秒,默认 86400)控制查询频率。
自更新检查只向 GitHub 请求 `main`;不发送遥测或标识符。

## 命令

| 命令 | 说明 |
|---|---|
| `omp-termux install [version\|file]` | 让本机用上该版本并安装插件(`latest` = 本仓库最新的构建,缺省 = 当前运行的版本);已是最新时不做任何事 |
| `omp-termux status` | 显示工具、omp、各个插件副本以及本仓库最新的构建 |
| `omp-termux verify` | 检查插件能否加载、omp 能否启动 |
| `omp-termux update-self` | 把已安装的 `omp-termux` 换成仓库里的最新版本 |
| `omp-termux uninstall-self` | 从本设备移除工具及其自更新缓存(omp 保留) |
| `omp-termux doctor` | 检查本设备的运行环境 |

## 注意事项

* Termux 上弹出软键盘会让画面从头滚到底,执行 `omp config set tui.resizeScrollback preserve` 可避免。
* Nerd Font 图标见 [docs/user/font.zh-CN.md](docs/user/font.zh-CN.md)(另有[英文版](docs/user/font.md))。
* Termux 会在 `omp` 每次写终端后把视图拉回底部;可以试试 `tmux`(`Ctrl-b [`),
  或用 Termux 0.119 及以后版本里的 `SCROLL`(`⇳`)。
  omp 18.4.1 到 18.5.0 空闲时也会每秒重绘,回滚后大约一秒就又被拉回底部。

## 限制

* Android 上没有桌面自动化和原生剪贴板;剪贴板回退到 `termux-clipboard-set`。
* Android 上没有音频、语音识别与语音合成支持。
* 只支持 arm64-v8a;armv7 与 x86 没有构建。

## 致谢与许可

Android 支持来自上游 [PR #6350](https://github.com/can1357/oh-my-pi/pull/6350)。
上游项目为 [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi);
该项目与本仓库均采用 MIT 许可,署名见 [LICENSE](LICENSE)。
