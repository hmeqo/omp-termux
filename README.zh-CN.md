# omp-termux

[English](README.md) | [中文](README.zh-CN.md)

`omp` 依赖原生插件 `@oh-my-pi/pi-natives`,而上游没有为 Android 构建它,所以在 Termux 上 omp 会以
`Unsupported platform: android-arm64` 退出。本仓库为 Termux 构建这个插件,并提供一个 `omp-termux` 命令,
让 omp 与插件始终保持同一版本。

## 环境要求

- Android 7.0 或更新的版本(API 24),aarch64
- `bash` 与 `curl`

## 安装

```sh
curl -fsSL https://raw.githubusercontent.com/hmeqo/omp-termux/main/install.sh | sh
```

需要指定版本时,在命令末尾加上版本号:

```sh
curl -fsSL https://raw.githubusercontent.com/hmeqo/omp-termux/main/install.sh | sh -s -- 18.3.4
```

装好后启动 `omp` 验证;如果它原本就在运行,请重启一次。安装脚本具体做了什么、更新检查如何工作:
[docs/user/install.zh-CN.md](docs/user/install.zh-CN.md)。

## 命令

| 命令 | 说明 |
|---|---|
| `omp-termux install [version\|file]` | 安装该版本及其插件(`latest` = 本仓库最新的构建,不填 = 已安装的版本);已是最新时不做任何改动 |
| `omp-termux status` | 显示工具、omp、各个插件副本,以及本仓库最新的构建 |
| `omp-termux verify` | 检查插件能否加载、omp 能否启动 |
| `omp-termux update-self` | 用本仓库最新的版本替换已安装的 `omp-termux` |
| `omp-termux uninstall-self` | 从本设备移除工具及其自更新缓存(omp 保留) |
| `omp-termux doctor` | 检查本设备的运行环境 |

## 注意事项

* 在 Termux 中打开软键盘时画面会从顶部滚动;执行 `omp config set tui.resizeScrollback preserve` 可避免。
* Nerd Font 图标见 [docs/user/font.zh-CN.md](docs/user/font.zh-CN.md)。
* `omp` 每次向终端输出,Termux 都会把视图拉回底部;可以试试 `tmux`(`Ctrl-b [`),
  或用 Termux 0.119 及以后版本里的 `SCROLL`(`⇳`)。
  omp 18.4.1 到 18.5.0 空闲时也会每秒重绘,所以回滚后大约一秒又会被拉回底部。

## 限制

* Android 上不支持桌面自动化和原生剪贴板,剪贴板改用 `termux-clipboard-set`。
* Android 上不支持音频、语音识别与语音合成。
* 只支持 arm64-v8a,armv7 与 x86 没有构建。

## 构建插件

`omp-termux-dev` 从源码交叉编译插件,并在设备可经 ssh 访问时安装与验证:[docs/dev/build.zh-CN.md](docs/dev/build.zh-CN.md)。设备端工具的设计见 [docs/dev/tool.zh-CN.md](docs/dev/tool.zh-CN.md)。

## 致谢与许可

Android 支持来自上游 [PR #6350](https://github.com/can1357/oh-my-pi/pull/6350)。
上游项目为 [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi);
该项目与本仓库均采用 MIT 许可,署名见 [LICENSE](LICENSE)。
